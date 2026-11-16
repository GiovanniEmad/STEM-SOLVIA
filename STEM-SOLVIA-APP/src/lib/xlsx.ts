import {zipSync,strToU8} from 'fflate';
// Minimal, dependency-light .xlsx writer (one sheet, numbers + inline strings).
const esc=(s:any)=>String(s??'').replace(/[\u0000-\u0008\u000b\u000c\u000e-\u001f]/g,'').replace(/[<>&"]/g,c=>({'<':'&lt;','>':'&gt;','&':'&amp;','"':'&quot;'} as Record<string,string>)[c]);
export const col=(i:number)=>{let s='',n=i+1;while(n>0){const m=(n-1)%26;s=String.fromCharCode(65+m)+s;n=Math.floor((n-1)/26);}return s;};
export function toXlsx(rows:Record<string,any>[],sheet='Sheet1'):Uint8Array{
 const keys=rows.length?Object.keys(rows[0]):[];
 const cell=(v:any,r:number,c:number)=>{const ref=col(c)+(r+1);return typeof v==='number'&&isFinite(v)?`<c r="${ref}"><v>${v}</v></c>`:`<c r="${ref}" t="inlineStr"><is><t xml:space="preserve">${esc(v)}</t></is></c>`;};
 const sd=[keys,...rows.map(r=>keys.map(k=>r[k]))].map((row,ri)=>`<row r="${ri+1}">${row.map((v,ci)=>cell(v,ri,ci)).join('')}</row>`).join('');
 const X='<?xml version="1.0" encoding="UTF-8" standalone="yes"?>';
 return zipSync({
  '[Content_Types].xml':strToU8(X+'<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/><Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/></Types>'),
  '_rels/.rels':strToU8(X+'<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>'),
  'xl/workbook.xml':strToU8(X+`<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets><sheet name="${esc(sheet).slice(0,31)}" sheetId="1" r:id="rId1"/></sheets></workbook>`),
  'xl/_rels/workbook.xml.rels':strToU8(X+'<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/></Relationships>'),
  'xl/worksheets/sheet1.xml':strToU8(X+`<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetData>${sd}</sheetData></worksheet>`)});}
// CSV formula-injection guard: cells that start with = + - @ are prefixed so spreadsheets do not evaluate them.
export const csvCell=(v:any)=>{let s=String(v??'');if(/^[=+\-@\t\r]/.test(s)&&isNaN(Number(s)))s="'"+s;return `"${s.replace(/"/g,'""')}"`;};
