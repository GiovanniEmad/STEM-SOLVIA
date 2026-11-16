import {useEffect,useState} from 'react';import {Link} from 'react-router-dom';import {BarChart,Bar,XAxis,YAxis,Tooltip,ResponsiveContainer} from 'recharts';import {supabase} from '../lib/supabase';import {rpc} from '../lib/api';import {hms} from '../lib/stopwatch';
export default function Dashboard(){const[p,setP]=useState<any>(null),[s,setS]=useState<any>(null),[ip,setIp]=useState<any[]>([]),[av,setAv]=useState(0),[nn,setNn]=useState<any[]>([]),[err,setErr]=useState('');
 useEffect(()=>{(async()=>{const{data:{user}}=await supabase.auth.getUser();if(!user)return;
  supabase.from('profiles').select('full_name,grade,schools(name)').eq('id',user.id).single().then(r=>r.error?setErr(r.error.message):setP(r.data));
  rpc('student_stats',{}).then(setS).catch(e=>setErr(e.message));
  supabase.from('exam_attempts').select('id,exams(title)').eq('status','in_progress').then(r=>setIp(r.data||[]));
  supabase.from('exams').select('id',{count:'exact',head:true}).eq('published',true).then(r=>setAv(r.count||0));
  supabase.from('notifications').select('id,title,created_at,read').order('created_at',{ascending:false}).limit(5).then(r=>setNn(r.data||[]));})();},[]);
 if(err)return<main><p role="alert">{err}</p></main>;if(!p||!s)return<main>Loading…</main>;
 const strong=s.by_topic.filter((t:any)=>t.pct>=75),weak=s.by_topic.filter((t:any)=>t.pct<60);
 return<main><h1>Welcome, {p.full_name.split(' ')[0]}</h1><p className="mut">{p.schools?.name} · Grade {p.grade}</p>
 <div className="grid"><div className="card"><div className="big">{av}</div>Available exams</div><div className="card"><div className="big">{s.completed}</div>Completed</div><div className="card"><div className="big">{s.avg??'—'}{s.avg!=null&&'%'}</div>Average score</div><div className="card"><div className="big">{hms(s.total_secs)}</div>Total solving time</div><div className="card"><div className="big">{s.practice}</div>Practice answers</div></div>
 <h2>Grades</h2><p>{[10,11,12].map(g=>g===p.grade?<b key={g}>Grade {g} ✓ </b>:<span key={g} className="mut">🔒 Grade {g} </span>)}</p>
 <h2>In progress</h2>{ip.length?ip.map(a=><div key={a.id}><Link to={'/exam/'+a.id}>{a.exams?.title} — continue</Link></div>):<p className="mut">Nothing in progress. <Link to="/exams">Browse exams</Link></p>}
 <h2>Performance by subject</h2>{s.by_subject.length?<div style={{height:220}}><ResponsiveContainer><BarChart data={s.by_subject}><XAxis dataKey="label"/><YAxis domain={[0,100]}/><Tooltip/><Bar dataKey="avg" fill="var(--ac)"/></BarChart></ResponsiveContainer></div>:<p className="mut">Submit an exam to see your performance.</p>}
 <h2>Recent results</h2>{s.history.length?<div className="scroll"><table><tbody>{s.history.slice(0,5).map((h:any,i:number)=><tr key={i}><td>{h.title}</td><td>{h.pct}%</td><td>{new Date(h.at).toLocaleDateString()}</td></tr>)}</tbody></table></div>:<p className="mut">No results yet.</p>}
 <h2>Topics</h2><p><b>Strong:</b> {strong.map((t:any)=>t.label).join(', ')||'—'}</p><p><b>To improve:</b> {weak.map((t:any)=>t.label).join(', ')||'—'}</p>
 <h2>Notifications</h2>{nn.length?nn.map(n=><div key={n.id}>{n.read?'':'● '}{n.title}</div>):<p className="mut">None.</p>}</main>;}
