import {ReactNode,useEffect,useState} from 'react';import {Link,useLocation,useNavigate} from 'react-router-dom';import {motion,useReducedMotion} from 'framer-motion';import katex from 'katex';import 'katex/dist/katex.min.css';import {supabase} from '../lib/supabase';
export function RichText({text}:{text:string}){const parts=(text||'').split(/(\$[^$]+\$)/g);
  return<span>{parts.map((p,i)=>p.length>2&&p.startsWith('$')&&p.endsWith('$')?<span key={i} dangerouslySetInnerHTML={{__html:katex.renderToString(p.slice(1,-1),{throwOnError:false})}}/>:<span key={i}>{p}</span>)}</span>;}
export function Img({path}:{path?:string|null}){const[u,setU]=useState(''),[bad,setBad]=useState(false);
  useEffect(()=>{if(path)supabase.storage.from('question-images').createSignedUrl(path,3600).then(r=>r.data?setU(r.data.signedUrl):setBad(true));},[path]);
  if(!path)return null;if(bad)return<em>Image unavailable</em>;return u?<img src={u} alt="Question figure" style={{maxWidth:'100%'}} onError={()=>setBad(true)}/>:<em>Loading image…</em>;}
export function Shell({children}:{children:ReactNode}){const[ok,setOk]=useState(false),[un,setUn]=useState(0),nav=useNavigate(),inExam=useLocation().pathname.startsWith('/exam/');
  useEffect(()=>{supabase.auth.getSession().then(({data})=>{if(!data.session){nav('/auth');return;}setOk(true);supabase.from('notifications').select('id',{count:'exact',head:true}).eq('read',false).then(r=>setUn(r.count||0));});},[nav]);
  if(!ok)return<p style={{padding:24}}>Loading…</p>;
  const th=()=>{const d=document.documentElement;d.dataset.theme=d.dataset.theme==='dark'?'light':'dark';};
  if(inExam)return<><nav className="top" aria-label="Main"><b>STEM SOLVIA</b><Link to="/dashboard">Exit to dashboard</Link></nav><Fade>{children}</Fade></>;
  return<><nav className="top" aria-label="Main"><b>STEM SOLVIA</b><Link to="/dashboard">Dashboard</Link><Link to="/exams">Exams</Link><Link to="/practice">Practice</Link><Link to="/saved">Saved</Link><Link to="/leaderboard">Leaderboard</Link><Link to="/notifications">Notifications{un?` (${un})`:''}</Link><Link to="/profile">Profile</Link>
   <button onClick={th} aria-label="Toggle theme">Theme</button><button onClick={async()=>{await supabase.auth.signOut();nav('/');}}>Sign out</button></nav><Fade>{children}</Fade></>;}

function Fade({children}:{children:ReactNode}){const r=useReducedMotion();return<motion.div initial={r?false:{opacity:0.01,y:6}} animate={{opacity:1,y:0}} transition={{duration:.18}}>{children}</motion.div>;}
