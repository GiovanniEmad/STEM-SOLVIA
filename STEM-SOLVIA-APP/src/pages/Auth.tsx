import {useEffect,useState} from 'react';import {Link} from 'react-router-dom';import {supabase} from '../lib/supabase';
type School={id:string;name:string};
export default function Auth(){
  const [up,setUp]=useState(false),[schools,setSchools]=useState<School[]>([]),[msg,setMsg]=useState('');
  const [f,setF]=useState({name:'',email:'',phone:'',school:'',grade:'10',pw:'',pw2:''});
  useEffect(()=>{supabase.from('schools').select('id,name').eq('active',true).order('name').then(r=>setSchools((r.data as School[])||[]));},[]);
  const [show,setShow]=useState(false);const set=(k:string)=>(e:any)=>setF({...f,[k]:e.target.value});
  async function go(e:React.FormEvent){e.preventDefault();setMsg('');
    if(!up){const{error}=await supabase.auth.signInWithPassword({email:f.email,password:f.pw});if(!error){location.href="/dashboard";return;}return setMsg(error.message);}
    if(f.name.trim().split(/\s+/).length<4)return setMsg('Enter four names.');
    if(!/^(\+20|0)1[0125]\d{8}$/.test(f.phone))return setMsg('Invalid Egyptian phone number.');
    if(f.pw.length<8||f.pw!==f.pw2)return setMsg('Password: min 8 chars and must match.');
    const dom=f.email.split('@')[1]?.toLowerCase();
    const{data:ok}=await supabase.from('school_domains').select('domain').eq('school_id',f.school).eq('domain',dom);
    if(!ok?.length)return setMsg('Email domain is not approved for this school.');
    const{error}=await supabase.auth.signUp({email:f.email,password:f.pw,options:{emailRedirectTo:location.origin+'/dashboard',data:{full_name:f.name,phone:f.phone,school_id:f.school,grade:+f.grade}}});
    if(error)return setMsg(error.message);
    setMsg('Check your email to verify your account.');}
  return(<main><form onSubmit={go} style={{display:'grid',gap:8,maxWidth:380,margin:'3rem auto',fontFamily:'system-ui'}}>
    <h1>{up?'Sign up':'Sign in'}</h1>
    {up&&<><label>Full name (4 names)<input value={f.name} onChange={set('name')} required/></label>
    <label>Phone<input value={f.phone} onChange={set('phone')} required/></label>
    <label>School<select value={f.school} onChange={set('school')} required><option value="">Select…</option>{schools.map(s=><option key={s.id} value={s.id}>{s.name}</option>)}</select></label>
    <label>Grade<select value={f.grade} onChange={set('grade')}><option>10</option><option>11</option><option>12</option></select></label></>}
    <label>School email<input type="email" value={f.email} onChange={set('email')} required/></label>
    <label>Password<input type={show?'text':'password'} value={f.pw} onChange={set('pw')} required/></label>
    {up&&<label>Confirm password<input type={show?'text':'password'} value={f.pw2} onChange={set('pw2')} required/></label>}
    <label><input type="checkbox" checked={show} onChange={()=>setShow(!show)}/> Show passwords</label><Link to="/recover">Forgot password?</Link><button>{up?'Create account':'Sign in'}</button><button type="button" onClick={()=>setUp(!up)}>{up?'Have an account?':'Need an account?'}</button><p role="alert">{msg}</p></form></main>);
}
