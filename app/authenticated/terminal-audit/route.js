import Route from '@ember/routing/route';
import { get } from '@ember/object';
import { inject as service } from '@ember/service';
import { hash } from 'rsvp';

export default Route.extend({
  globalStore: service(),

  model() {
    return hash({
      status:   this.requestStatus(),
      commands: this.requestCommands({ limit: 100 }),
    });
  },

  setupController(controller, model) {
    this._super(controller, model);
    controller.set('commands', get(model, 'commands.data') || []);
    controller.set('commandCount', get(model, 'commands.count') || 0);
  },

  requestStatus() {
    return get(this, 'globalStore').rawRequest({
      url:    '/v3/terminal-audit/status',
      method: 'GET',
    }).then((res) => get(res, 'body')).catch(() => ({}));
  },

  requestCommands(params = {}) {
    const query = Object.keys(params).filter((key) => params[key]).map((key) => {
      return `${ encodeURIComponent(key) }=${ encodeURIComponent(params[key]) }`;
    }).join('&');

    return get(this, 'globalStore').rawRequest({
      url:    `/v3/terminal-audit/commands${ query ? `?${ query }` : '' }`,
      method: 'GET',
    }).then((res) => get(res, 'body')).catch(() => ({
      data:  [],
      count: 0,
    }));
  },

});
