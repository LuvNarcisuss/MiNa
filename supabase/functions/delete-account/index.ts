import { createClient } from 'npm:@supabase/supabase-js@2';
const headers = {'Access-Control-Allow-Origin':'*','Access-Control-Allow-Headers':'authorization, apikey, content-type','Content-Type':'application/json'};
const reply=(status:number,message:string)=>new Response(JSON.stringify({message}),{status,headers});
Deno.serve(async req=>{
  if(req.method==='OPTIONS')return new Response(null,{headers});
  if(req.method!=='POST'||(await req.json().catch(()=>({}))).confirm!==true)return reply(400,'Confirm account deletion.');
  const token=req.headers.get('Authorization')?.replace(/^Bearer /,'');
  if(!token)return reply(401,'Sign in to continue.');
  const service=createClient(Deno.env.get('SUPABASE_URL')!,Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
  const {data,error}=await service.auth.getUser(token);
  if(error||!data.user)return reply(401,'Your session has expired.');
  const id=data.user.id;
  const bucket=service.storage.from('mina-media');
  while(true){
    const {data:files,error:listError}=await bucket.list(id,{limit:100});
    if(listError)return reply(503,'Could not read account media. Try again.');
    if(!files?.length)break;
    const {error:removeError}=await bucket.remove(files.map(file=>id+'/'+file.name));
    if(removeError)return reply(503,'Could not clear account media. Try again.');
  }
  const {error:deletionError}=await service.auth.admin.deleteUser(id);
  return deletionError?reply(503,'Could not finish deletion. Try again.'):reply(200,'Account deleted.');
});
