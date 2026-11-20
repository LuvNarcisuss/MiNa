import documents from './documents.json' with {type:'json'};
Deno.serve(req=>{
  const filename=new URL(req.url).pathname.split('/').pop();
  if((req.method!=='GET'&&req.method!=='HEAD')||(filename!=='terms.pdf'&&filename!=='privacy.pdf'))return new Response(null,{status:404});
  const bytes=Uint8Array.from(atob(documents[filename]),c=>c.charCodeAt(0));
  return new Response(req.method==='HEAD'?null:bytes,{headers:{'Content-Type':'application/pdf','Content-Disposition':'inline; filename="'+filename+'"','Cache-Control':'public, max-age=3600','Access-Control-Allow-Origin':'*'}});
});
