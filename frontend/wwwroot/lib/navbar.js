// Determine active tab
var pathname = window.location.pathname.substring(1,6)
var title    = window.location.pathname.split('/')[1].split('.')[0].split('_').join(" / ")
$(document).attr("title", title)
var agree_class, users_class, group_class, usage_class
switch(pathname) {
case "agree": agree_class = 'active'; break
case "deliv": agree_class = 'active'; break
case "users": users_class = 'active'; break
case "group": group_class = 'active'; break
case "usage": usage_class = 'active'; break
}
// Create navbar and interpolate active tab
$("body").prepend(`
<ul class="nav nav-tabs" style="font-size: 16pt;">
  <li class="${agree_class}"><a class="text-capitalize" href="agreements.html">${agree_class ? title : 'Agreements'}</a></li>
  <li class="${users_class}"><a class="text-capitalize" href="users.html">${users_class ? title : 'Users'}</a></li>
  <li class="${group_class}"><a class="text-capitalize" href="groups.html">${group_class ? title : 'Groups'}</a></li>
  <li class="${usage_class}"><a class="text-capitalize" href="usage.html">${usage_class ? title : 'Usage'}</a></li>
  <div id="pagination" style="position: fixed; top: 0; right: 2;"><div>
</ul>
`)

function pagination(url, page) {
    var html = `
  <ul class="pagination" style="margin-top: 3px;">
    ${ page > 0 ? '<li class="page-item"><a class="page-link" href="'+url+'&page='+(parseFloat(page)-1)+'">&laquo;</a></li>' : ''}
    ${ page > 0 ? '<li class="page-item disabled active"><a class="page-link">'+parseFloat(page)+'</a></li>' : ''}
    <li class="page-item"><a class="page-link" href="${url}&page=${parseFloat(page)+1}">&raquo;</a></li>
  </ul>`
    $("#pagination").html(html)
}
