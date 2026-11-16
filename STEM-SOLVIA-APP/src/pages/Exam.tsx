import {useCallback,useEffect,useRef,useState} from 'react';import {useParams} from 'react-router-dom';import {supabase} from '../lib/supabase';import {rpc} from '../lib/api';import {elapsedSeconds,hms} from '../lib/stopwatch';import {RichText,Img} from '../components/ui';import {shuf} from '../lib/shuffle';
type Save='saved'|'saving'|'error';
export default function Exam(){
  const {id}=useParams(),[att,setAtt]=useState<any>(null),[qs,setQs]=useState<any[]>([]),[ans,setAns]=useState<Record<string,string>>({}),[i,setI]=useState(0),
   [tick,setTick]=useState(0),[save,setSave]=useState<Save>('saved'),[confirm,setConfirm]=useState(false),[res,setRes]=useState<any>(null),[err,setErr]=useState('');
  const pending=useRef<Record<string,string>>({});
  const loadAtt=useCallback(async()=>{const{data,error}=await supabase.from('exam_attempts').select('*').eq('id',id).single();if(error)throw error;setAtt(data);return data;},[id]);
  useEffect(()=>{(async()=>{try{
    const a=await loadAtt();
    if(a.status==='submitted'){setRes(await rpc('get_result',{p_attempt:a.id}));return;}
    const q=await supabase.from('exam_questions').select('position,questions(id,text,image_path,marks,question_options(opt_id,text,image_path))').eq('exam_id',a.exam_id).order('position');
    const s=await supabase.from('student_answers').select('question_id,chosen_opt').eq('attempt_id',a.id);
    setAns(Object.fromEntries((s.data||[]).map((x:any)=>[x.question_id,x.chosen_opt])));
    const fl:any=(await supabase.from('exams').select('shuffle_questions,shuffle_options').eq('id',a.exam_id).single()).data||{};let list:any[]=(q.data||[]).map((r:any)=>({...r.questions,options:[...r.questions.question_options].sort((x:any,y:any)=>x.opt_id.localeCompare(y.opt_id))}));if(fl.shuffle_questions)list=shuf(list,a.id);if(fl.shuffle_options)list=list.map((x:any)=>({...x,options:shuf(x.options,a.id+x.id)}));setQs(list);
  }catch(e:any){setErr(e.message);}})();},[loadAtt]);
  useEffect(()=>{const t=setInterval(()=>setTick(x=>x+1),1000);return()=>clearInterval(t);},[]);
  const flush=useCallback(async()=>{const items=Object.entries(pending.current);if(!items.length||!att)return;setSave('saving');
    for(const[q,o]of items){try{await rpc('save_answer',{p_attempt:att.id,p_q:q,p_opt:o});if(pending.current[q]===o)delete pending.current[q];}catch{setSave('error');return;}}
    setSave('saved');},[att]);
  useEffect(()=>{const t=setInterval(flush,4000);window.addEventListener('online',flush);return()=>{clearInterval(t);window.removeEventListener('online',flush);};},[flush]);
  const pick=(q:string,o:string)=>{setAns(a=>({...a,[q]:o}));pending.current[q]=o;flush();};
  async function clock(run:boolean){try{await rpc('set_clock',{p_attempt:att.id,p_run:run});await loadAtt();}catch(e:any){setErr(e.message);}}
  async function mark(q:string){try{const m=await rpc<string[]>('toggle_mark',{p_attempt:att.id,p_q:q});setAtt({...att,marked:m});}catch(e:any){setErr(e.message);}}
  async function submit(){await flush();if(Object.keys(pending.current).length)return setErr('Unsaved answers — check your connection and retry.');
    try{setRes(await rpc('submit_attempt',{p_attempt:att.id}));setConfirm(false);}catch(e:any){setErr(e.message);}}
  if(err&&!att)return<p role="alert">{err}</p>;if(!att)return<p>Loading…</p>;
  if(res)return(<main style={{fontFamily:'system-ui',padding:24,maxWidth:700,margin:'auto'}}><h1>Result</h1>{res.hidden?<p>Results are not available yet{res.release_at?` (release: ${new Date(res.release_at).toLocaleString()})`:''}. Time: {hms(res.time_seconds)}</p>:<><p>Score {res.score}/{res.total} ({res.percentage}%)</p><p>Correct {res.correct} · Incorrect {res.incorrect} · Unanswered {res.unanswered} · Time {hms(res.time_seconds)}</p>
   {(res.review||[]).map((r:any,k:number)=><div key={k}><b>{k+1}. <RichText text={r.text}/></b><div>Your answer: {r.chosen_text??'—'} · Correct: {r.correct_text}</div>{r.explanation&&<small>{r.explanation}</small>}</div>)}</>}</main>);
  const q=qs[i];void tick;const el=elapsedSeconds(att),marked:string[]=att.marked||[],answered=qs.filter(x=>ans[x.id]).length;
  return(<main style={{fontFamily:'system-ui',padding:16,maxWidth:760,margin:'auto'}}><h1 className="sr-only">Examination</h1>
   <header style={{display:'flex',justifyContent:'space-between'}}><b aria-live="off">⏱ {hms(el)}{att.running_since?'':' (paused)'}</b>
    <span>{save==='saving'?'Saving…':save==='saved'?'Saved':'Save failed — retrying'}</span>
    <button onClick={()=>clock(!att.running_since)}>{att.running_since?'Pause':'Resume'}</button></header>
   {err&&<p role="alert">{err}</p>}
   <progress value={answered} max={qs.length||1} style={{width:'100%'}}/> <small>{answered}/{qs.length} answered</small>
   {q&&<section><h2>Q{i+1}. <RichText text={q.text}/></h2><Img path={q.image_path}/>
    {q.options.map((o:any,oi:number)=><label key={o.opt_id} style={{display:'block',padding:8,border:'1px solid #8884',margin:4,borderRadius:6}}><input type="radio" name={q.id} checked={ans[q.id]===o.opt_id} disabled={!att.running_since} onChange={()=>pick(q.id,o.opt_id)}/> {'ABCDEFGH'[oi]}. <RichText text={o.text}/><Img path={o.image_path}/></label>)}
    <button onClick={()=>mark(q.id)}>{marked.includes(q.id)?'Unmark review':'Mark for review'}</button>
    <button disabled={i===0} onClick={()=>setI(i-1)}>Previous</button><button disabled={i>=qs.length-1} onClick={()=>setI(i+1)}>Next</button></section>}
   <nav aria-label="Questions" style={{display:'flex',flexWrap:'wrap',gap:4,margin:'12px 0'}}>{qs.map((x,k)=><button key={x.id} onClick={()=>setI(k)} style={{fontWeight:k===i?700:400,background:marked.includes(x.id)?'#fc6':ans[x.id]?'#9d9':'transparent'}}>{k+1}</button>)}</nav>
   <button onClick={()=>setConfirm(true)}>Submit</button>
   {confirm&&<div role="dialog" aria-modal="true" style={{border:'2px solid',padding:16,marginTop:12}}><p>Total {qs.length} · Answered {answered} · Unanswered {qs.length-answered} · Marked {marked.length} · Time {hms(el)}</p><button onClick={submit}>Confirm submit</button><button onClick={()=>setConfirm(false)}>Cancel</button></div>}
  </main>);
}
