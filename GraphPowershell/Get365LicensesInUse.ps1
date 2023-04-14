#Get All Licenses
Get-MgSubscribedSku | select skupartnumber,consumedunits,@{n="PaidUnits";e={(Get-MgSubscribedSku -SubscribedSkuId $_.ID).prepaidunits.enabled}}

#Get only Office 365/Microsoft365 Licenses
Get-MgSubscribedSku | where-object {($_.skupartnumber -like "*pack*")  -or ($_.skupartnumber -like "*SPE*")}| select skupartnumber,consumedunits,@{n="PaidUnits";e={(Get-MgSubscribedSku -SubscribedSkuId $_.ID).prepaidunits.enabled}}
