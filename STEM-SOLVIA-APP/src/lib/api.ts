import {supabase} from './supabase';
export const rpc=async<T=any>(fn:string,args:Record<string,unknown>):Promise<T>=>{const{data,error}=await supabase.rpc(fn,args);if(error)throw error;return data as T;};
