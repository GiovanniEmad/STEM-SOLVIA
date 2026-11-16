import {useState} from 'react';import {validateImport} from '../lib/importValidator';import {rpc} from '../lib/api';
const T=['mcq-template','mcq-image-template','mcq-mathematical-template','mixed-exam-mcq-template'];
async function sha(s:string){const b=await crypto.subtle.digest('SHA-256',new TextEncoder().encode(s));return[...new Uint8Array(b)].map(x=>x.toString(16).padStart(2,'0')).join('');}
export default function Import(){
  const [t,setT]=useState(''),[r,setR]=useState<ReturnType<typeof validateImport>|null>(null),[rep,setRep]=useState<any>(null),[err,setErr]=useState(''),[busy,setBusy]=useState(false);
  const edit=(i:number,patch:any)=>{const d=JSON.parse(t);d.questions[i]={...d.questions[i],...patch};const s=JSON.stringify(d,null,1);setT(s);setR(validateImport(s));};
  async function commit(){setErr('');setBusy(true);try{setRep(await rpc('import_exam',{p:JSON.parse(t),p_hash:await sha(t.trim())}));}catch(e:any){setErr(e.message);}setBusy(false);}
  return(<section><h2>Bulk MCQ import</h2><p>Templates: {T.map(n=><a key={n} href={`/templates/${n}.json`} download style={{marginRight:8}}>{n}.json</a>)}</p>
    <input type="file" aria-label="JSON file" accept=".json" onChange={async e=>{const f=e.target.files?.[0];if(f){setT(await f.text());setR(null);setRep(null);}}}/>
    <textarea aria-label="JSON" rows={10} style={{width:'100%'}} value={t} onChange={e=>{setT(e.target.value);setR(null);}}/>
    <button onClick={()=>setR(validateImport(t))}>Validate &amp; preview</button>
    {r&&!r.ok&&<ul role="alert">{r.issues.map((i,k)=><li key={k}>{i.index<0?'File':'#'+(i.index+1)} {i.id}: {i.error}</li>)}</ul>}
    {r?.data&&<><p>{r.ok?'Valid':'Fix the highlighted problems'}: {r.data.questions.length} questions in <b>{r.data.exam?.title}</b>. Edit below; changes update the JSON.</p>
     <div className="scroll"><table><thead><tr><th>#</th><th>Question</th><th>Marks</th><th>Correct</th></tr></thead><tbody>{r.data.questions.map((q:any,i:number)=>{const bad=r.issues.some(x=>x.index===i);return<tr key={i} style={bad?{background:'#d6454533'}:{}}><td>{i+1}</td>
      <td><input aria-label={`Question ${i+1}`} style={{width:'100%'}} value={q.question_text||''} onChange={e=>edit(i,{question_text:e.target.value})}/></td>
      <td><input aria-label="Marks" type="number" style={{width:60}} value={q.marks??''} onChange={e=>edit(i,{marks:+e.target.value})}/></td>
      <td><select aria-label="Correct answer" value={q.correct_answer||''} onChange={e=>edit(i,{correct_answer:e.target.value})}><option value=""/>{(q.options||[]).map((o:any)=><option key={o.id}>{o.id}</option>)}</select></td></tr>;})}</tbody></table></div>
     <button disabled={busy||!r.ok} onClick={commit}>Import (creates an unpublished exam)</button></>}
    {err&&<p role="alert">Rejected by server — nothing imported: {err}</p>}
    {rep&&<p>Import report: {rep.imported}/{rep.total} imported, {rep.rejected} rejected. Exam id {rep.exam_id}</p>}</section>);
}
