<template>
  <div v-if="serverConfig.happydeliver && serverConfig.happydeliver.enabled" class="box">
    <h3 class="title is-size-6">
      {{ $t('campaigns.testDeliverability') }}
    </h3>

    <p class="help mb-2">{{ $t('campaigns.testDeliverabilityHelp') }}</p>

    <b-field v-if="state === 'idle' || state === 'error'"
      :label="$t('campaigns.testDeliverabilityAsSub')" label-position="on-border">
      <b-input v-model="asSub" type="email" icon="account-outline"
        :disabled="isNew" :placeholder="$t('campaigns.testDeliverabilityAsSubPlaceholder')" />
    </b-field>

    <b-field v-if="state === 'idle'">
      <b-button @click="runTest" :loading="loading.campaigns" :disabled="isNew"
        type="is-primary" icon-left="shield-check-outline">
        {{ $t('campaigns.runDeliverabilityTest') }}
      </b-button>
    </b-field>

    <div v-else-if="state === 'pending'" class="has-text-centered">
      <p class="is-size-6">
        <b-icon icon="loading" custom-class="mdi-spin" size="is-small" />
        {{ $t('campaigns.deliverabilityPending', { seconds: elapsedSec }) }}
      </p>
      <p v-if="testEmail" class="is-size-7 has-text-grey mt-1">
        {{ testEmail }}
      </p>
    </div>

    <div v-else-if="state === 'done' && report">
      <div class="has-text-centered mb-3">
        <span class="tag is-large" :class="gradeTagClass(report.grade)">
          {{ report.grade }}
        </span>
        <p class="is-size-6 mt-1">
          {{ $t('campaigns.deliverabilityScore') }}:
          <strong>{{ report.score }}&nbsp;/&nbsp;100</strong>
        </p>
      </div>

      <table v-if="report.summary" class="table is-fullwidth is-narrow is-size-7">
        <tbody>
          <tr v-for="row in breakdown" :key="row.key">
            <td>{{ row.label }}</td>
            <td class="has-text-right">
              <span class="mr-1">{{ row.score }}</span>
              <span class="tag" :class="gradeTagClass(row.grade)">{{ row.grade }}</span>
            </td>
          </tr>
        </tbody>
      </table>

      <b-field grouped group-multiline>
        <p class="control is-expanded">
          <a :href="reportUrl" target="_blank" rel="noopener noreferrer"
            class="button is-primary is-outlined is-fullwidth">
            <b-icon icon="open-in-new" size="is-small" />
            <span>{{ $t('campaigns.deliverabilityViewFullReport') }}</span>
          </a>
        </p>
        <p class="control is-expanded">
          <b-button expanded @click="reset" icon-left="refresh">
            {{ $t('campaigns.deliverabilityRunNew') }}
          </b-button>
        </p>
      </b-field>
    </div>

    <div v-else-if="state === 'error'">
      <b-message type="is-danger" :closable="false" size="is-small">
        {{ $t('campaigns.deliverabilityError', { error: error || '' }) }}
      </b-message>
      <b-field>
        <b-button @click="runTest" type="is-primary" icon-left="refresh">
          {{ $t('campaigns.deliverabilityRunNew') }}
        </b-button>
      </b-field>
    </div>
  </div>
</template>

<script>
import Vue from 'vue';
import { mapState } from 'vuex';

export default Vue.extend({
  props: {
    campaign: { type: Object, required: true },
    campaignId: { type: Number, default: 0 },
    isNew: { type: Boolean, default: false },
  },

  data() {
    return {
      asSub: '',
      state: 'idle', // idle | pending | done | error
      testId: null,
      testEmail: null,
      report: null,
      error: null,
      elapsedSec: 0,
      pollHandle: null,
      tickHandle: null,
    };
  },

  computed: {
    ...mapState(['serverConfig', 'loading']),

    reportUrl() {
      if (!this.testId || !this.serverConfig.happydeliver) return '#';
      const base = String(this.serverConfig.happydeliver.url || '').replace(/\/+$/, '');
      return `${base}/test/${encodeURIComponent(this.testId)}`;
    },

    breakdown() {
      const s = this.report && this.report.summary;
      if (!s) return [];
      // Backend proxies happyDeliver JSON verbatim; listmonk's axios interceptor
      // converts snake_case to camelCase (dns_score → dnsScore, etc).
      return [
        {
          key: 'dns', label: 'DNS', grade: s.dnsGrade, score: s.dnsScore,
        },
        {
          key: 'auth', label: this.$t('campaigns.deliverabilityAuth'), grade: s.authenticationGrade, score: s.authenticationScore,
        },
        {
          key: 'spam', label: this.$t('campaigns.deliverabilitySpam'), grade: s.spamGrade, score: s.spamScore,
        },
        {
          key: 'blacklist', label: this.$t('campaigns.deliverabilityBlacklist'), grade: s.blacklistGrade, score: s.blacklistScore,
        },
        {
          key: 'header', label: this.$t('campaigns.deliverabilityHeader'), grade: s.headerGrade, score: s.headerScore,
        },
        {
          key: 'content', label: this.$t('campaigns.deliverabilityContent'), grade: s.contentGrade, score: s.contentScore,
        },
      ].filter((r) => r.grade !== undefined);
    },
  },

  methods: {
    runTest() {
      this.clearTimers();

      const subs = this.asSub && this.asSub.trim() !== ''
        ? [this.asSub.trim()]
        : [];

      const c = this.campaign;
      const data = {
        id: this.campaignId,
        name: c.name,
        subject: c.subject,
        lists: c.lists.map((l) => l.id),
        from_email: c.fromEmail,
        messenger: c.messenger,
        type: 'regular',
        headers: c.headers,
        tags: c.tags,
        template_id: c.content.templateId,
        content_type: c.content.contentType,
        body: c.content.body,
        altbody: c.content.contentType !== 'plain' ? c.altbody : null,
        subscribers: subs,
        media: c.media.map((m) => m.id),
      };

      this.state = 'pending';
      this.testId = null;
      this.testEmail = null;
      this.report = null;
      this.error = null;
      this.elapsedSec = 0;

      this.$api.testCampaignDeliverability(data).then((resp) => {
        if (!resp || !resp.testId) {
          this.state = 'error';
          this.error = 'invalid response';
          return;
        }
        this.testId = resp.testId;
        this.testEmail = resp.testEmail;

        this.tickHandle = setInterval(() => {
          this.elapsedSec += 1;
          if (this.elapsedSec > 300) {
            this.state = 'error';
            this.error = 'timeout';
            this.clearTimers();
          }
        }, 1000);

        this.pollHandle = setInterval(() => {
          this.poll();
        }, 4000);
      }).catch((err) => {
        this.state = 'error';
        this.error = (err && err.message) ? err.message : String(err);
      });
    },

    poll() {
      const { testId } = this;
      if (!testId) return;

      this.$api.getDeliverabilityStatus(testId).then((status) => {
        if (!status || this.testId !== testId) return;
        if (status.status === 'analyzed') {
          this.clearTimers();
          this.$api.getDeliverabilityReport(testId).then((report) => {
            if (this.testId !== testId) return;
            this.report = report;
            this.state = 'done';
          }).catch((err) => {
            this.state = 'error';
            this.error = (err && err.message) ? err.message : String(err);
          });
        }
      }).catch((err) => {
        this.clearTimers();
        this.state = 'error';
        this.error = (err && err.message) ? err.message : String(err);
      });
    },

    reset() {
      this.clearTimers();
      this.state = 'idle';
      this.testId = null;
      this.testEmail = null;
      this.report = null;
      this.error = null;
      this.elapsedSec = 0;
    },

    clearTimers() {
      if (this.pollHandle) {
        clearInterval(this.pollHandle);
        this.pollHandle = null;
      }
      if (this.tickHandle) {
        clearInterval(this.tickHandle);
        this.tickHandle = null;
      }
    },

    gradeTagClass(grade) {
      if (!grade) return 'is-light';
      const g = String(grade).toUpperCase();
      if (g.startsWith('A')) return 'is-success';
      if (g.startsWith('B')) return 'is-info';
      if (g.startsWith('C')) return 'is-warning';
      return 'is-danger';
    },
  },

  beforeDestroy() {
    this.clearTimers();
  },
});
</script>
