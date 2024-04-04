$mailbox = get-mailbox -filter {windowsemailaddress -like "*domain.com"} -ResultSize unlimited | select name,userprincipalname,forwardingsmtpaddress,delivertomailboxandforward,forwardingaddress
$rules = @()
foreach ($m in $mailbox) {
$rules += get-inboxrule -Mailbox $M.userprincipalname | select @{n="Userprincipalname";e={$m.userprincipalname}},name,description,enabled,from,redirectto,forwardto,ForwardAsAttachmentTo
}
