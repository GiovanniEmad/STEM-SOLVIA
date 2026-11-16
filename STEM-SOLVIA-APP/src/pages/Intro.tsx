import {useEffect,useState} from 'react';import {useNavigate,useParams} from 'react-router-dom';import {supabase} from '../lib/supabase';import {rpc} from '../lib/api';
export default function Intro(){const{id}=useParams(),nav=useNavigate(),[e,setE]=useState<any>(null),[err,setErr]=useState('');
 useEffect(()=>{supabase.from('exams').select('title,description,instructions,suggested_minutes,total_marks,exam_questions(count)').eq('id',id).single().then(r=>r.error?setErr(r.error.message):setE(r.data));},[id]);
 async function go(){try{nav('/exam/'+await rpc<string>('start_attempt',{p_exam:id}));}catch(x:any){setErr(x.message);}}
 if(err)return<main><p role="alert">{err}</p></main>;if(!e)return<main>Loading…</main>;
 return<main><h1>{e.title}</h1><p>{e.description}</p><div className="card"><p>{e.exam_questions?.[0]?.count} multiple-choice questions · {e.total_marks} marks</p>
 {e.suggested_minutes&&<p className="mut">Historical duration: {e.suggested_minutes} min (informational only — there is no time limit).</p>}
 <p>{e.instructions||'Choose one answer per question. Your answers save automatically. A stopwatch counts up so you can see how long you take; you can pause it, leave, and resume later. Submit when you are ready.'}</p>
 <button onClick={go}>Start or continue</button></div></main>;}
