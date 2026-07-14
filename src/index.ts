import { registerPlugin } from '@capacitor/core';

import type { WalkMePlugin } from './definitions';

const WalkMe = registerPlugin<WalkMePlugin>('WalkMe', {
  web: () => import('./web').then((m) => new m.WalkMeWeb()),
});

export * from './definitions';
export { WalkMe };
