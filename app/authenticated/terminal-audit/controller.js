import Controller from '@ember/controller';
import { computed, get, set } from '@ember/object';
import { inject as service } from '@ember/service';
import Errors from 'shared/utils/errors';

export default Controller.extend({
  globalStore: service(),
  growl:       service(),

  sessionId:       '',
  user:            '',
  asset:           '',
  account:         '',
  input:           '',
  limit:           100,
  loadingCommands: false,

  replayDate:     '',
  replaySession:  '',
  replayFilename: '',
  replayUrl:      '',
  replayKey:      '',
  loadingReplay:  false,

  actions: {
    refreshStatus() {
      return this.requestStatus();
    },

    searchCommands() {
      set(this, 'loadingCommands', true);

      return this.requestCommands(this.commandFilterParams()).finally(() => {
        set(this, 'loadingCommands', false);
      });
    },

    clearCommandFilters() {
      set(this, 'sessionId', '');
      set(this, 'user', '');
      set(this, 'asset', '');
      set(this, 'account', '');
      set(this, 'input', '');
      set(this, 'limit', 100);
      this.send('searchCommands');
    },

    loadReplayUrl() {
      const sessionId = get(this, 'replaySession');
      const filename = get(this, 'replayFilename');
      const date = get(this, 'replayDate');

      if (!sessionId || !filename) {
        get(this, 'growl').fromError('Missing replay input', 'Session and file name are required.');

        return;
      }

      set(this, 'loadingReplay', true);
      set(this, 'replayUrl', '');
      set(this, 'replayKey', '');

      const query = date ? `?date=${ encodeURIComponent(date) }` : '';

      return get(this, 'globalStore').rawRequest({
        url:    `/v3/terminal-audit/replays/${ encodeURIComponent(sessionId) }/${ encodeURIComponent(filename) }/url${ query }`,
        method: 'GET',
      }).then((res) => {
        set(this, 'replayUrl', get(res, 'body.url') || '');
        set(this, 'replayKey', get(res, 'body.key') || '');
      }).catch((err) => {
        get(this, 'growl').fromError('Failed to load replay URL', Errors.stringify(err));
      })
        .finally(() => {
          set(this, 'loadingReplay', false);
        });
    },
  },

  status: computed('model.status', function() {
    return get(this, 'model.status') || {};
  }),

  commandRows: computed('commands.[]', function() {
    return (get(this, 'commands') || []).map((row) => {
      const timestamp = get(row, 'timestamp');

      return {
        raw:              row,
        user:             get(row, 'user') || '-',
        asset:            get(row, 'asset') || '-',
        account:          get(row, 'account') || '-',
        session:          get(row, 'session') || '-',
        input:            get(row, 'input') || '-',
        output:           get(row, 'output') || '',
        riskLevel:        get(row, 'riskLevel') || 0,
        timestampDisplay: timestamp ? new Date(timestamp * 1000).toLocaleString() : '-',
      };
    });
  }),

  commandFilterParams() {
    return {
      sessionId: get(this, 'sessionId'),
      user:      get(this, 'user'),
      asset:     get(this, 'asset'),
      account:   get(this, 'account'),
      input:     get(this, 'input'),
      limit:     get(this, 'limit') || 100,
    };
  },

  requestStatus() {
    return get(this, 'globalStore').rawRequest({
      url:    '/v3/terminal-audit/status',
      method: 'GET',
    }).then((res) => {
      set(this, 'model.status', get(res, 'body') || {});
    }).catch((err) => {
      get(this, 'growl').fromError('Failed to load terminal audit status', Errors.stringify(err));
    });
  },

  requestCommands(params) {
    const query = Object.keys(params).filter((key) => params[key]).map((key) => {
      return `${ encodeURIComponent(key) }=${ encodeURIComponent(params[key]) }`;
    }).join('&');

    return get(this, 'globalStore').rawRequest({
      url:    `/v3/terminal-audit/commands${ query ? `?${ query }` : '' }`,
      method: 'GET',
    }).then((res) => {
      set(this, 'commands', get(res, 'body.data') || []);
      set(this, 'commandCount', get(res, 'body.count') || 0);
    }).catch((err) => {
      get(this, 'growl').fromError('Failed to load command audit records', Errors.stringify(err));
    });
  },
});
