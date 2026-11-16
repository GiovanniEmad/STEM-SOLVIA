export interface ImportIssue{ index:number; id?:string; error:string }
export function validateImport(raw:string):{ok:boolean;issues:ImportIssue[];data?:any}{
  let d:any; const issues:ImportIssue[]=[];
  try{ d=JSON.parse(raw);}catch(e){return{ok:false,issues:[{index:-1,error:'Invalid JSON: '+(e as Error).message}]};}
  if(!d.exam?.title) issues.push({index:-1,error:'exam.title missing'});
  if(!Array.isArray(d.questions)||!d.questions.length) return{ok:false,issues:[...issues,{index:-1,error:'questions[] missing or empty'}]};
  const seen=new Set<string>();
  d.questions.forEach((q:any,i:number)=>{
    const e=(error:string)=>issues.push({index:i,id:q?.question_id,error});
    if(q.question_type!=='MCQ') e(`Unsupported question_type "${q.question_type}" (only MCQ)`);
    if(!q.question_id) e('question_id missing'); else if(seen.has(q.question_id)) e('duplicate question_id'); else seen.add(q.question_id);
    if(!q.question_text?.trim()) e('question_text missing');
    const ids=(q.options||[]).map((o:any)=>o.id);
    if(ids.length<2) e('needs at least 2 options');
    if(new Set(ids).size!==ids.length||ids.some((x:any)=>!x)) e('option ids must be unique and non-empty');
    if((q.options||[]).some((o:any)=>!o.text?.trim())) e('option text missing');
    if(typeof q.correct_answer!=='string'||!ids.includes(q.correct_answer)) e('correct_answer must match exactly one option id');
    if(!(typeof q.marks==='number'&&q.marks>0)) e('marks must be a positive number');
  });
  return{ok:!issues.length,issues,data:d};
}
