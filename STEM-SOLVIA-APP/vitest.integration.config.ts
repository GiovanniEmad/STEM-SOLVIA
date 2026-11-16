import {defineConfig} from 'vitest/config';import react from '@vitejs/plugin-react';
export default defineConfig({plugins:[react()],test:{include:['src/__integration__/**/*.itest.{ts,tsx}'],fileParallelism:false,testTimeout:40000,css:false}});
