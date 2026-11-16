import {describe,it,expect} from 'vitest';import {validateImport} from '../lib/importValidator';import {elapsedSeconds,hms} from '../lib/stopwatch';
const q=(o:any={})=>({question_id:'A1',question_text:'t',question_type:'MCQ',options:[{id:'A',text:'x'},{id:'B',text:'y'}],correct_answer:'A',marks:1,...o});
const doc=(qs:any[])=>JSON.stringify({exam:{title:'E'},questions:qs});
const bad=(o:any)=>validateImport(doc([q(o)])).ok;
describe('import validator',()=>{
 it('accepts valid MCQ',()=>expect(validateImport(doc([q()])).ok).toBe(true));
 it('rejects invalid JSON',()=>expect(validateImport('{').ok).toBe(false));
 it('rejects unsupported type',()=>expect(bad({question_type:'TF'})).toBe(false));
 it('rejects duplicate question ids',()=>expect(validateImport(doc([q(),q()])).ok).toBe(false));
 it('rejects duplicate option ids',()=>expect(bad({options:[{id:'A',text:'x'},{id:'A',text:'y'}]})).toBe(false));
 it('rejects missing/invalid correct answer',()=>{expect(bad({correct_answer:undefined})).toBe(false);expect(bad({correct_answer:'Z'})).toBe(false);});
 it('rejects bad marks',()=>{expect(bad({marks:0})).toBe(false);expect(bad({marks:'1'})).toBe(false);});
 it('rejects <2 options',()=>expect(bad({options:[{id:'A',text:'x'}]})).toBe(false));
 it('handles 500 questions',()=>expect(validateImport(doc(Array.from({length:500},(_,i)=>q({question_id:'Q'+i})))).ok).toBe(true));
});
describe('stopwatch',()=>{
 it('counts upward from stored + running time',()=>expect(elapsedSeconds({elapsed_seconds:60,running_since:new Date(0).toISOString()},5000)).toBe(65));
 it('does not advance while paused',()=>expect(elapsedSeconds({elapsed_seconds:60,running_since:null},9e9)).toBe(60));
 it('supports multi-day',()=>expect(hms(3*86400+5)).toBe('72:00:05'));
});
import {shuf} from '../lib/shuffle';
describe('shuffle',()=>{
 it('is a deterministic permutation',()=>{const a=[1,2,3,4,5,6,7,8];const x=shuf(a,'att1');expect(shuf(a,'att1')).toEqual(x);expect([...x].sort()).toEqual(a);});
 it('differs per seed',()=>expect(shuf(Array.from({length:20},(_,i)=>i),'a')).not.toEqual(shuf(Array.from({length:20},(_,i)=>i),'b')));
});
import {toXlsx,col,csvCell} from '../lib/xlsx';import {unzipSync,strFromU8} from 'fflate';import fs from 'fs';
describe('xlsx export',()=>{
 it('writes a valid package with numbers and escaped strings',()=>{const u=toXlsx([{label:'A & <B>',avg:75.5,n:3}],'by_exam');fs.writeFileSync('/tmp/out.xlsx',u);const z=unzipSync(u);
  expect(Object.keys(z).sort()).toEqual(['[Content_Types].xml','_rels/.rels','xl/_rels/workbook.xml.rels','xl/workbook.xml','xl/worksheets/sheet1.xml']);
  const sh=strFromU8(z['xl/worksheets/sheet1.xml']);expect(sh).toContain('A &amp; &lt;B&gt;');expect(sh).toContain('<v>75.5</v>');});
 it('column letters',()=>{expect([col(0),col(25),col(26),col(701),col(702)]).toEqual(['A','Z','AA','ZZ','AAA']);});
 it('csv formula-injection guard',()=>{expect(csvCell('=HYPERLINK("x")')).toBe(`"'=HYPERLINK(""x"")"`);expect(csvCell(-5)).toBe('"-5"');expect(csvCell('ok')).toBe('"ok"');});
});
