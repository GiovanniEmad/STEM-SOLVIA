import {useEffect,useState} from 'react';import {supabase} from '../lib/supabase';import {rpc} from '../lib/api';
export default function Notifications(){const[n,setN]=useState<any[]>([]),[ld,setLd]=useState(true);
 const load=()=>supabase.from('notifications').select('*').order('created_at',{ascending:false}).limit(100).then(r=>{setN(r.data||[]);setLd(false);});useEffect(()=>{load();},[]);
 return<main><h1>Notifications</h1><button onClick={async()=>{await rpc('mark_read',{});load();}}>Mark all as read</button>{ld&&<p>Loading…</p>}{!ld&&!n.length&&<p className="mut">No notifications.</p>}
 {n.map(x=><div className="card" key={x.id} style={{margin:'8px 0',opacity:x.read?.6:1}}><b>{x.title}</b><div>{x.body}</div><small className="mut">{new Date(x.created_at).toLocaleString()}</small> {!x.read&&<button onClick={async()=>{await rpc('mark_read',{p_id:x.id});load();}}>Mark read</button>}</div>)}</main>;}
