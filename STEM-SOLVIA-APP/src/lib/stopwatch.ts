// Timestamp-based: elapsed = saved seconds + (now - running_since). Survives refresh, no max, no auto-submit.
export function elapsedSeconds(a:{elapsed_seconds:number;running_since:string|null}, now=Date.now()):number{
  return a.elapsed_seconds + (a.running_since ? Math.max(0, Math.floor((now - Date.parse(a.running_since))/1000)) : 0);
}
export const hms=(s:number)=>[Math.floor(s/3600),Math.floor(s/60)%60,s%60].map(n=>String(n).padStart(2,'0')).join(':');
