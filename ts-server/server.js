import 'dotenv/config';
import { start } from './src/index.js';

start().catch((err) => {
  console.error(err);
  process.exit(1);
});
