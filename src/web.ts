import { WebPlugin } from '@capacitor/core';

import type {
  WalkMePlugin,
  WalkMeStartOptions,
  SetVariableOptions,
  StartItemOptions,
  SendEventOptions,
  WalkMeEventUserVarsKey,
} from './definitions';

/**
 * Browser fallback used during `ionic serve` / web builds. WalkMe has no
 * web runtime, so every call is a logged no-op rather than a native bridge
 * call. This lets the demo app run in a browser for fast iteration on
 * layout/navigation without a device.
 */
export class WalkMeWeb extends WebPlugin implements WalkMePlugin {
  private warn(method: string) {
    console.warn(`[WalkMe] "${method}" has no web implementation — running on a real device is required.`);
  }

  async start(_options: WalkMeStartOptions): Promise<void> {
    this.warn('start');
  }

  async stop(): Promise<void> {
    this.warn('stop');
  }

  async restart(): Promise<void> {
    this.warn('restart');
  }

  async setUserId(_options: { userId: string | null }): Promise<void> {
    this.warn('setUserId');
  }

  async setLanguage(_options: { language: string }): Promise<void> {
    this.warn('setLanguage');
  }

  async setVariable(_options: SetVariableOptions): Promise<void> {
    this.warn('setVariable');
  }

  async setEventUserVars(_options: { values: Partial<Record<WalkMeEventUserVarsKey, string>> }): Promise<void> {
    this.warn('setEventUserVars');
  }

  async setTenantId(_options: { tenantId: string | null }): Promise<void> {
    this.warn('setTenantId');
  }

  async startItemByID(_options: StartItemOptions): Promise<void> {
    this.warn('startItemByID');
  }

  async dismissItem(): Promise<void> {
    this.warn('dismissItem');
  }

  async sendEvent(_options: SendEventOptions): Promise<void> {
    this.warn('sendEvent');
  }

  async getVariant(): Promise<{ variant: 'standard' | 'editor' }> {
    this.warn('getVariant');
    return { variant: 'standard' };
  }
}
