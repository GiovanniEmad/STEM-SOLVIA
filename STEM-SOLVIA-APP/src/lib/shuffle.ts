// Deterministic seeded shuffle: the same attempt always sees the same order after a refresh.
export function shuf<T>(a:T[],seed:string):T[]{let h=1779033703^seed.length;for(const ch of seed){h=Math.imul(h^ch.charCodeAt(0),3432918353);h=(h<<13)|(h>>>19);}
 const r=()=>{h=Math.imul(h^(h>>>16),2246822507);h=Math.imul(h^(h>>>13),3266489909);h^=h>>>16;return(h>>>0)/4294967296;};
 const b=[...a];for(let i=b.length-1;i>0;i--){const j=Math.floor(r()*(i+1));[b[i],b[j]]=[b[j],b[i]];}return b;}
