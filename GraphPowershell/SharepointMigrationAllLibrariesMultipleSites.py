import asyncio
import httpx
import os
import time
import csv
import json
from datetime import datetime
from azure.identity import InteractiveBrowserCredential
from azure.identity.aio import DefaultAzureCredential
from azure.storage.blob.aio import BlobServiceClient

# ==========================================
# 1. HARDCODED CONFIGURATION
# ==========================================
ENVIRONMENT = "LOCAL" 

if ENVIRONMENT == "LOCAL":
    WORKER_COUNT = 20
    CHUNK_SIZE = 4 * 1024 * 1024 
else:
    WORKER_COUNT = 30  
    CHUNK_SIZE = 4 * 1024 * 1024 

# Changed from CSV to TXT
SITES_TXT_FILE = "c:\\temp\\MigrationSP-SA\\sites_to_migrate.txt" 
STORAGE_ACCOUNT_URL = ""
PHL_STORAGE_ACCOUNT_URL = ""

EXCLUDED_LIBRARIES = ["style library", "formservertemplates", "siteassets", "site pages"]
PHL_LIBRARIES = ["preservation hold library", "permanentes dokumentarchiv"]

# Files
RUN_TIMESTAMP = datetime.now().strftime("%Y%m%d_%H%M%S")
CSV_ERROR_FILE = f"migration_errors_{RUN_TIMESTAMP}.csv"
CSV_HISTORY_FILE = "migration_history.csv"

# ==========================================
# 2. SITE CONTEXT & STATE MANAGEMENT
# ==========================================
class SiteMigrationContext:
    def __init__(self, site_url):
        self.site_url = site_url
        self.clean_url = site_url.strip("/")
        self.site_name = self.clean_url.split("/")[-1]
        self.safe_site_name = "".join(c for c in self.site_name.lower() if c.isalnum())
        self.destination_container_name = self.safe_site_name
        self.scan_cache_filename = f"migration_scan_cache_{self.safe_site_name}.json"
        
        self.abort_event = asyncio.Event()
        self.abort_reason = "Unknown"
        
        self.stats = {
            "total_scanned": 0,
            "total_completed": 0,
            "transferred": 0,
            "skipped": 0,
            "errors": 0
        }
        
        # Two distinct indexes for the two storage accounts
        self.blob_index = {}
        self.phl_blob_index = {}
        
        self.error_log = []
        self.library_reports = []

    def trigger_abort(self, reason="UNKNOWN"):
        if not self.abort_event.is_set():
            self.abort_reason = reason
            print(f"\n⛔ CRITICAL STOP FOR SITE [{self.site_name}]: {reason}")
            print(f"   ⚡ KILL SWITCH ACTIVATED. TERMINATING WORKERS FOR THIS SITE...")
            self.abort_event.set()

async def watchdog(workers, context):
    await context.abort_event.wait()
    for w in workers: 
        w.cancel()

# ==========================================
# 3. TOKEN MANAGER
# ==========================================
class TokenManager:
    def __init__(self, cred):
        self.cred = cred
        self.access_token = None
        self.expires_at = 0
    
    async def get_valid_token(self, context=None):
        if context and context.abort_event.is_set(): 
            return None

        if not self.access_token or time.time() > self.expires_at - 300:
            try:
                token_obj = await asyncio.to_thread(
                    self.cred.get_token,
                    "https://graph.microsoft.com/Sites.Read.All",
                    "https://graph.microsoft.com/Files.Read.All"
                )
                self.access_token = token_obj.token
                self.expires_at = token_obj.expires_on
            except Exception as e:
                err_msg = str(e)
                if "AADSTS70043" in err_msg or "InteractionRequired" in err_msg or "invalid_grant" in err_msg:
                    if context:
                        context.trigger_abort(reason="REFRESH TOKEN EXPIRED")
                    raise asyncio.CancelledError() 
                
                print(f"\n⛔ CRITICAL: FAILED TO GET TOKEN ({err_msg[:50]})...")
                raise Exception("TOKEN_ACQUISITION_FAILED")
        return self.access_token

# ==========================================
# 4. CORE LOGIC
# ==========================================
async def get_site_info(client, context, token):
    hostname = context.site_url.split("://")[1].split("/")[0]
    rel_path = "/" + "/".join(context.clean_url.split("/")[3:])
    url = f"https://graph.microsoft.com/v1.0/sites/{hostname}:{rel_path}"
    headers = {"Authorization": f"Bearer {token}"}
    
    resp = await client.get(url, headers=headers)
    
    if resp.status_code != 200:
        print(f"\n❌ API ERROR: Failed to resolve Site {context.site_url}. HTTP {resp.status_code}")
        print(f"   Response: {resp.text}")
        return None
        
    data = resp.json()
    print(f"\n✅ Site successfully resolved: {data.get('displayName')}")
    return data['id']

async def get_all_drives(client, site_id, token):
    url = f"https://graph.microsoft.com/v1.0/sites/{site_id}/drives"
    headers = {"Authorization": f"Bearer {token}"}
    drives = []
    
    print(f"📂 Asking Microsoft Graph for libraries...")
    
    while url:
        resp = await client.get(url, headers=headers)
        
        if resp.status_code != 200:
            print(f"❌ API ERROR ({resp.status_code}) on Drives endpoint:")
            print(f"   {resp.text}")
            break
            
        data = resp.json()
        batch = data.get('value', [])
        print(f"   - API returned {len(batch)} raw libraries.")
        
        for d in batch:
            if d['name'].lower() in EXCLUDED_LIBRARIES:
                print(f"     🚫 Skipping excluded library: {d['name']}")
            else:
                print(f"     ✅ Adding target library: {d['name']}")
                drives.append(d)
                
        url = data.get('@odata.nextLink')
        
    return drives

async def scan_drive_files_with_cloud_cache(client, drive_id, drive_name, token_manager, cache_container_client, context):
    cache_key = f"{drive_id}_{drive_name}"
    full_cache = {}

    try:
        blob_client = cache_container_client.get_blob_client(context.scan_cache_filename)
        if await blob_client.exists():
            print(f"   ☁️  Downloading cache from Azure ({context.scan_cache_filename})...", end="\r")
            download_stream = await blob_client.download_blob()
            data = await download_stream.readall()
            full_cache = json.loads(data)
    except Exception as e:
        print(f"   ⚠️ Could not read cache from Azure: {e}")

    if cache_key in full_cache:
        cached_files = full_cache[cache_key]
        print(f"   💾 Cache Hit! Loaded {len(cached_files)} files from Azure Blob.")
        return cached_files

    print(f"   ⏳ No cloud cache found. Scanning API... (Pages so far: 0)", end="\r")
    
    url = f"https://graph.microsoft.com/v1.0/drives/{drive_id}/root/delta?$select=id,name,size,file,parentReference"
    files = []
    page_count = 0
    
    while url:
        if context.abort_event.is_set(): break

        token = await token_manager.get_valid_token(context)
        headers = {"Authorization": f"Bearer {token}"}

        try:
            resp = await client.get(url, headers=headers, timeout=60)
            
            if resp.status_code == 401:
                print("\n   ⚠️ Token expired during scan. Aborting scan for this lib.")
                return [] 
                
            if resp.status_code == 429:
                wait = int(resp.headers.get("Retry-After", 10))
                print(f"\n   ⚠️ Throttled scanning API. Waiting {wait}s...")
                await asyncio.sleep(wait)
                continue

            data = resp.json()
            new_files = [i for i in data.get('value', []) if 'file' in i]
            files.extend(new_files)
            
            page_count += 1
            if page_count % 10 == 0:
                print(f"   ⏳ Scanning API... (Items found: {len(files)})", end="\r")

            url = data.get('@odata.nextLink')
            
        except Exception as e:
            print(f"\n   ❌ Error scanning page {page_count}: {e}")
            break
            
    print(f"   ✅ API Scan Complete. Found {len(files)} items.        ")
    
    if not context.abort_event.is_set():
        try:
            full_cache[cache_key] = files
            cache_json = json.dumps(full_cache)
            print(f"   ☁️  Uploading updated cache to Azure...", end="\r")
            await cache_container_client.get_blob_client(context.scan_cache_filename).upload_blob(cache_json, overwrite=True)
            print(f"   💾 Saved scan results to Azure Blob: {context.scan_cache_filename}")
        except Exception as e:
            print(f"   ❌ Failed to save cache to Azure: {e}")

    return files

async def build_resume_index(container_client, target_index_dict, context):
    print(f"🔍 Checking Azure Container '{context.destination_container_name}' in {container_client.account_name}...")
    if not await container_client.exists(): await container_client.create_container()
    
    count = 0
    print("   ⏳ Building resume index... (this may take a while)", end="\r")
    async for b in container_client.list_blobs():
        clean_path = b.name.replace("\\", "/").strip("/").lower()
        target_index_dict[clean_path] = b.size
        count += 1
        if count % 5000 == 0:
            print(f"   ⏳ Building resume index... ({count} files indexed)", end="\r")
            
    print(f"   > Index ready: {len(target_index_dict)} files found.           ")

async def prune_and_update_cache(files, lib_name, cache_container_client, drive_id, active_index_dict, context):
    files_to_process = []
    skipped_count = 0
    size_mismatches_ignored = 0

    print(f"   🧹 Pruning list based on Azure Index...", flush=True)
    
    for item in files:
        file_name = item['name']
        file_size = item['size']
        raw_path = item.get('parentReference', {}).get('path', '')
        folder_path = raw_path.split("root:/")[1] if "root:/" in raw_path else ""
        blob_path = os.path.join(lib_name, folder_path, file_name).replace("\\", "/").strip("/")
        check_path = blob_path.lower()

        if check_path in active_index_dict:
            azure_size = active_index_dict[check_path]
            
            # 1. Exact Match
            if azure_size == file_size:
                skipped_count += 1
                
            # 2. Both are zero bytes
            elif azure_size == 0 and file_size == 0:
                skipped_count += 1
                
            # 3. Size Similarity Math (The Safe Fallback)
            elif file_size > 0 and azure_size > 0:
                diff_bytes = abs(file_size - azure_size)
                
                # Allow a 5% difference, OR a maximum of 5MB (whichever is smaller).
                # This protects large files from being skipped if they are missing big chunks.
                max_allowed_diff = min(file_size * 0.05, 5 * 1024 * 1024) 
                
                if diff_bytes <= max_allowed_diff:
                    skipped_count += 1
                    size_mismatches_ignored += 1
                else:
                    files_to_process.append(item) # Diff is too large, re-queue it
            else:
                files_to_process.append(item)
        else:
            files_to_process.append(item)
    
    print(f"   ✂️  Removed {skipped_count} completed files from queue (Safely ignored {size_mismatches_ignored} metadata size mismatches).", flush=True)
    print(f"   📉 Remaining To-Do: {len(files_to_process)} files.", flush=True)

    # ALWAYS UPDATE AZURE CACHE
    try:
        blob_client = cache_container_client.get_blob_client(context.scan_cache_filename)
        
        full_cache = {}
        if await blob_client.exists():
            download_stream = await blob_client.download_blob()
            data = await download_stream.readall()
            full_cache = json.loads(data)
            
        cache_key = f"{drive_id}_{lib_name}"
        full_cache[cache_key] = files_to_process
        
        cache_json = json.dumps(full_cache)
        print(f"   ☁️  Updating Cache in Azure...", end="\r", flush=True)
        await blob_client.upload_blob(cache_json, overwrite=True)
        print(f"   💾 Cache Updated! Next run will start perfectly from here.              ", flush=True)
    except Exception as e:
        print(f"   ⚠️ Failed to update pruned cache: {e}", flush=True)

    return files_to_process

async def migration_worker(worker_id, queue, client, container_client, drive_id, lib_name, token_manager, lib_total, lib_stats, context):
    try:
        while not queue.empty():
            if context.abort_event.is_set(): return

            try:
                item = queue.get_nowait()
            except asyncio.QueueEmpty:
                break

            try:
                await transfer_single_file(client, container_client, item, drive_id, lib_name, token_manager, lib_total, lib_stats, context)
            except asyncio.CancelledError:
                raise 
            except Exception as e:
                print(f"Worker {worker_id} error on {item.get('name', 'unknown')}: {e}")
            finally:
                queue.task_done()
    except asyncio.CancelledError:
        return 

async def transfer_single_file(client, container_client, item, drive_id, lib_name, token_manager, lib_total, lib_stats, context):
    if context.abort_event.is_set(): return

    file_name = item['name']
    file_size = item['size']
    size_mb = round(file_size / (1024 * 1024), 2)
    
    raw_path = item.get('parentReference', {}).get('path', '')
    folder_path = raw_path.split("root:/")[1] if "root:/" in raw_path else ""
    blob_path = os.path.join(lib_name, folder_path, file_name).replace("\\", "/").strip("/")
    
    status_icon = ""
    size_str = f"{size_mb}MB"
    
    # --- NEW: Print before starting large files so we know what is hanging! ---
    if file_size > CHUNK_SIZE:
        print(f"   ⏳ [Worker] Starting stream: {size_str} | {file_name}")

    try:
        if file_size == 0:
            await container_client.get_blob_client(blob_path).upload_blob(b"", overwrite=True)
            context.stats["transferred"] += 1
            lib_stats["transferred"] += 1
            status_icon = "✅ Empty"
            size_str = "0MB"
        else:
            url = None
            current_token = await token_manager.get_valid_token(context)
            headers = {"Authorization": f"Bearer {current_token}"}
            jit_url = f"https://graph.microsoft.com/v1.0/drives/{drive_id}/items/{item['id']}?$select=@microsoft.graph.downloadUrl"

            max_retries = 5 
            for attempt in range(1, max_retries + 1):
                if context.abort_event.is_set(): raise asyncio.CancelledError()

                try:
                    jit = await client.get(jit_url, headers=headers)
                    
                    if jit.status_code == 200:
                        url = jit.json().get('@microsoft.graph.downloadUrl')
                        if url: break 
                    elif jit.status_code == 401: 
                        context.trigger_abort("HTTP 401 UNAUTHORIZED")
                        raise asyncio.CancelledError()
                    elif jit.status_code == 429: 
                        wait_time = int(jit.headers.get("Retry-After", 5)) * attempt
                        await asyncio.sleep(wait_time)
                    elif jit.status_code in [503, 504]: 
                        await asyncio.sleep(2 * attempt)
                        
                except Exception as e:
                    if context.abort_event.is_set(): raise asyncio.CancelledError()
                    pass
                await asyncio.sleep(1) 

            if not url:
                if context.abort_event.is_set(): raise asyncio.CancelledError()
                raise Exception(f"No URL (HTTP {jit.status_code if 'jit' in locals() else 'Unknown'})")

            if file_size < CHUNK_SIZE:
                file_resp = await client.get(url, timeout=60)
                if file_resp.status_code == 200:
                    await container_client.get_blob_client(blob_path).upload_blob(file_resp.content, overwrite=True)
                    context.stats["transferred"] += 1
                    lib_stats["transferred"] += 1
                    status_icon = "✅"
                elif file_resp.status_code == 401:
                    context.trigger_abort("HTTP 401 DURING DOWNLOAD")
                    raise asyncio.CancelledError()
                else: raise Exception(f"DL HTTP {file_resp.status_code}")
            else:
                # --- NEW: Added a read timeout to prevent infinite hangs ---
                stream_timeout = httpx.Timeout(60.0, read=300.0)
                
                async with client.stream("GET", url, timeout=stream_timeout) as resp:
                    if resp.status_code == 200:
                        await container_client.get_blob_client(blob_path).upload_blob(
                            resp.aiter_bytes(chunk_size=CHUNK_SIZE), 
                            overwrite=True, max_concurrency=4, length=file_size 
                        )
                        context.stats["transferred"] += 1
                        lib_stats["transferred"] += 1
                        status_icon = "✅"
                    elif resp.status_code == 401:
                        context.trigger_abort("HTTP 401 DURING STREAM")
                        raise asyncio.CancelledError()
                    else: raise Exception(f"Stream HTTP {resp.status_code}")

    except asyncio.CancelledError:
        raise 
    except Exception as e:
        err_msg = str(e)
        context.stats["errors"] += 1
        lib_stats["errors"] += 1
        status_icon = f"❌ {err_msg[:25]}"
        context.error_log.append([context.site_name, lib_name, file_name, blob_path, err_msg])
        
    finally:
        if not context.abort_event.is_set():
            lib_stats["processed"] += 1
            context.stats["total_completed"] += 1
            lib_p = round((lib_stats["processed"] / lib_total) * 100, 1) if lib_total > 0 else 0
            
            # --- NEW: Print success/fail at the end, and ignore the 50-file rule for large files ---
            if "Error" in status_icon or lib_stats["processed"] % 50 == 0 or file_size > CHUNK_SIZE or lib_total < 50:
                print(f"[Lib: {lib_stats['processed']}/{lib_total} ({lib_p}%)] {status_icon} {size_str} | {file_name}")

async def process_site(context, client, std_blob_service, phl_blob_service, token_manager):
    start_time = time.time()
    print(f"\n" + "="*70)
    print(f"🚀 INITIATING MIGRATION FOR SITE: {context.site_name}")
    print("="*70)

    try:
        first_token = await token_manager.get_valid_token(context)
        
        site_id = await get_site_info(client, context, first_token)
        if not site_id:
            print(f"⏭️ Skipping site {context.site_url} due to resolution error.")
            return

        drives = await get_all_drives(client, site_id, first_token)
        if not drives:
            print("⏭️ Skipping site: No target libraries found.")
            return

        # Check if PHL exists on this specific site to avoid creating empty storage containers
        has_phl = any(d['name'].lower() in PHL_LIBRARIES for d in drives)

        # Setup Standard Library Container & Index
        std_container_client = std_blob_service.get_container_client(context.destination_container_name)
        if not await std_container_client.exists(): await std_container_client.create_container()
        await build_resume_index(std_container_client, context.blob_index, context)

        # Setup PHL Container & Index (Only if needed)
        phl_container_client = None
        if has_phl:
            phl_container_client = phl_blob_service.get_container_client(context.destination_container_name)
            if not await phl_container_client.exists(): await phl_container_client.create_container()
            await build_resume_index(phl_container_client, context.phl_blob_index, context)
        
        print("🔍 Pre-scanning libraries...")
        drive_data = []
        for d in drives:
            is_phl = d['name'].lower() in PHL_LIBRARIES
            active_cc = phl_container_client if is_phl else std_container_client
            active_idx = context.phl_blob_index if is_phl else context.blob_index

            files = await scan_drive_files_with_cloud_cache(client, d['id'], d['name'], token_manager, active_cc, context)
            if files:
                files_to_do = await prune_and_update_cache(files, d['name'], active_cc, d['id'], active_idx, context)
                if files_to_do:
                    context.stats["total_scanned"] += len(files_to_do)
                    drive_data.append((d, files_to_do, is_phl))
        
        if not drive_data:
            print("✅ Site is already fully migrated! Moving to next site.")
            return

        print(f"🚀 Found {context.stats['total_scanned']} files remaining. Starting Migration...")

        for drive, files, is_phl in drive_data:
            if context.abort_event.is_set(): break

            lib_name = drive['name']
            account_target = "PHL Storage" if is_phl else "Standard Storage"
            print(f"\n📂 STARTED Library: [{lib_name}] -> {account_target} ({len(files)} remaining files)")
            
            lib_stats = {"name": lib_name, "processed": 0, "transferred": 0, "skipped": 0, "errors": 0}
            active_cc = phl_container_client if is_phl else std_container_client
            
            file_queue = asyncio.Queue()
            for f in files: file_queue.put_nowait(f)
            
            workers = []
            for i in range(WORKER_COUNT):
                task = asyncio.create_task(
                    migration_worker(i, file_queue, client, active_cc, drive['id'], lib_name, token_manager, len(files), lib_stats, context)
                )
                workers.append(task)
            
            watchdog_task = asyncio.create_task(watchdog(workers, context))

            await asyncio.gather(*workers, return_exceptions=True)
            
            if not watchdog_task.done(): watchdog_task.cancel()
            context.library_reports.append(lib_stats)

    except Exception as e: 
        print(f"\n💥 CRITICAL ERROR ON SITE {context.site_name}: {e}")
        
    finally:
        # --- REPORTING ---
        if context.error_log:
            file_exists = os.path.isfile(CSV_ERROR_FILE)
            with open(CSV_ERROR_FILE, "a", newline="", encoding="utf-8") as f:
                writer = csv.writer(f)
                if not file_exists:
                    writer.writerow(["Site Name", "Library", "File Name", "Full Path", "Error Message"])
                writer.writerows(context.error_log)
            print(f"\n⚠️  Errors logged to: {CSV_ERROR_FILE}")

        duration = round((time.time() - start_time) / 60, 2)
        
        file_exists = os.path.isfile(CSV_HISTORY_FILE)
        with open(CSV_HISTORY_FILE, "a", newline="", encoding="utf-8") as f:
            writer = csv.writer(f)
            if not file_exists:
                writer.writerow(["Run Date", "Site Name", "Duration (min)", "Total Files", "Transferred", "Skipped", "Errors", "Error Log File"])
            writer.writerow([RUN_TIMESTAMP, context.site_name, duration, context.stats['total_scanned'], context.stats['transferred'], context.stats['skipped'], context.stats['errors'], CSV_ERROR_FILE])
        
        total = context.stats['total_scanned']
        trans_p = round((context.stats['transferred'] / total) * 100, 1) if total > 0 else 0.0
        err_p = round((context.stats['errors'] / total) * 100, 1) if total > 0 else 0.0

        print("\n" + "="*70)
        print(f"       MIGRATION REPORT - {context.safe_site_name}")
        if context.abort_event.is_set():
            print(f"       ⚠️  STOPPED EARLY: {context.abort_reason} ⚠️")
        print("="*70)
        print(f" TOTAL TIME       : {duration} Minutes")
        print(f" TOTAL REMAINING  : {total}")
        print(f" ✅ TRANSFERRED   : {context.stats['transferred']} ({trans_p}%)")
        print(f" ❌ FAILED        : {context.stats['errors']} ({err_p}%)")
        print("-" * 70)
        print(" PER LIBRARY BREAKDOWN:")
        print("-" * 70)
        print(f" {'LIBRARY NAME':<35} | {'MOVED':<8} | {'FAIL':<8}")
        print("-" * 70)
        for report in context.library_reports:
            print(f" {report['name'][:33]:<35} | {report['transferred']:<8} | {report['errors']:<8}")
        print("="*70 + "\n")

async def main():
    print("📋 Reading Sites from TXT...")
    if not os.path.isfile(SITES_TXT_FILE):
        print(f"⛔ ABORTING: Cannot find {SITES_TXT_FILE}")
        return

    urls = []
    with open(SITES_TXT_FILE, "r", encoding="utf-8-sig") as f:
        for line in f:
            clean_line = line.strip()
            if clean_line and clean_line.startswith("http"):
                urls.append(clean_line)
    
    if not urls:
        print("⛔ ABORTING: No valid URLs found in TXT file.")
        return

    print(f"🚀 Found {len(urls)} sites to process.")
    print("🌐 Requesting Graph API login...")
    
    graph_cred = InteractiveBrowserCredential(client_id="14d82eec-204b-4c2f-b7e8-296a70dab67e")
    token_manager = TokenManager(graph_cred)
    storage_cred = DefaultAzureCredential()

    try:
        await token_manager.get_valid_token()
        print("✅ Initial Graph API Token Acquired!")
        
        async with BlobServiceClient(STORAGE_ACCOUNT_URL, credential=storage_cred) as std_blob_service, \
                   BlobServiceClient(PHL_STORAGE_ACCOUNT_URL, credential=storage_cred) as phl_blob_service:
            async with httpx.AsyncClient(timeout=None) as client:
                for url in urls:
                    context = SiteMigrationContext(url)
                    await process_site(context, client, std_blob_service, phl_blob_service, token_manager)

    except Exception as e: 
        print(f"\n💥 GLOBAL ERROR: {e}")
        
    finally:
        await storage_cred.close()
        await asyncio.sleep(0.25)
        print("🏁 BATCH MIGRATION COMPLETE.")

if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        print("\n🚫 Script cancelled by user.")
