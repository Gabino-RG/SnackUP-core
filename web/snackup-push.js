/* Browser-only Push API bridge. Authentication stays in the Dart API client. */
(() => {
  'use strict';
  const base = new URL('.', document.currentScript.src);
  const workerUrl = new URL('snackup-push-sw.js', base);
  // A dedicated scope avoids replacing Flutter's optional offline worker.
  const scopeUrl = new URL('push/', base);
  const encode = value => JSON.stringify(value);
  const supported = () => window.isSecureContext &&
    'serviceWorker' in navigator && 'PushManager' in window &&
    'Notification' in window;
  let activeAttempt = null;
  let pendingPermission = null;
  let pendingSubscription = null;

  async function bounded(operation, milliseconds = 10000) {
    let timer;
    try {
      return await Promise.race([operation, new Promise((_, reject) => {
        timer = setTimeout(() => reject(new Error('PUSH_TIMEOUT')), milliseconds);
      })]);
    } finally { clearTimeout(timer); }
  }

  function cancelActivation() {
    if (activeAttempt) activeAttempt.cancel('PUSH_CANCELLED');
  }

  function beginAttempt() {
    let reject;
    const cancelled = new Promise((_, fail) => { reject = fail; });
    // Cancellation can occur between steps, when no race is awaiting it.
    cancelled.catch(() => {});
    const attempt = {
      cancelled: false,
      cancel(code) {
        if (!attempt.cancelled) {
          attempt.cancelled = true;
          reject(new Error(code));
        }
      },
      async step(start) {
        if (attempt.cancelled) throw new Error('PUSH_CANCELLED');
        // start() executes synchronously, preserving the permission gesture.
        const result = await Promise.race([start(), cancelled]);
        if (attempt.cancelled) throw new Error('PUSH_CANCELLED');
        return result;
      }
    };
    attempt.timer = setTimeout(() => attempt.cancel('PUSH_TIMEOUT'), 25000);
    return attempt;
  }

  function requestPermission() {
    if (pendingPermission) throw new Error('PUSH_PENDING');
    const operation = Notification.requestPermission();
    pendingPermission = operation;
    const finished = () => {
      if (pendingPermission === operation) pendingPermission = null;
    };
    operation.then(finished, finished);
    return operation;
  }

  function subscribe(worker, key, attempt) {
    // The browser API has no AbortSignal. Keep a late operation isolated until
    // it settles; a cancelled subscription is never returned to Dart/API.
    const operation = worker.pushManager.subscribe({
      userVisibleOnly: true, applicationServerKey: key
    }).then(async subscription => {
      if (attempt.cancelled) {
        await subscription.unsubscribe();
        return null;
      }
      return subscription;
    });
    pendingSubscription = operation;
    const finished = () => {
      if (pendingSubscription === operation) pendingSubscription = null;
    };
    operation.then(finished, finished);
    return operation;
  }

  async function registration() {
    if (!supported()) return null;
    const found = await navigator.serviceWorker.getRegistration(scopeUrl.href);
    return found && found.scope === scopeUrl.href ? found : null;
  }

  async function activeRegistration() {
    const result = await navigator.serviceWorker.register(workerUrl.href, {
      scope: scopeUrl.href,
      updateViaCache: 'none'
    });
    if (result.active) return result;
    const worker = result.installing || result.waiting;
    if (!worker) throw new Error('WORKER_UNAVAILABLE');
    await new Promise((resolve, reject) => {
      const finish = error => {
        clearTimeout(timeout);
        worker.removeEventListener('statechange', changed);
        error ? reject(error) : resolve();
      };
      const changed = () => {
        if (worker.state === 'activated') finish();
        if (worker.state === 'redundant') finish(new Error('WORKER_UNAVAILABLE'));
      };
      const timeout = setTimeout(() => finish(new Error('WORKER_UNAVAILABLE')), 15000);
      worker.addEventListener('statechange', changed);
      changed();
    });
    return result;
  }

  function applicationKey(value) {
    if (typeof value !== 'string' || !/^[A-Za-z0-9_-]+$/.test(value)) {
      throw new Error('INVALID_PUBLIC_KEY');
    }
    const raw = atob(value.replace(/-/g, '+').replace(/_/g, '/') +
      '='.repeat((4 - value.length % 4) % 4));
    const bytes = Uint8Array.from(raw, character => character.charCodeAt(0));
    if (bytes.length !== 65 || bytes[0] !== 4) throw new Error('INVALID_PUBLIC_KEY');
    return bytes;
  }

  function failure(error) {
    const name = error && error.name;
    const code = error && error.message;
    // Do not return browser exception text: it may contain a subscription URL.
    return encode({error: name === 'NotAllowedError' ? 'PERMISSION_DENIED' :
      ['INVALID_PUBLIC_KEY', 'PUSH_TIMEOUT', 'PUSH_PENDING', 'PUSH_CANCELLED'].includes(code)
        ? code : 'PUSH_UNAVAILABLE'});
  }

  window.snackupPush = Object.freeze({
    async status() {
      if (!supported()) return encode({supported: false,
        reason: window.isSecureContext ? 'UNSUPPORTED' : 'INSECURE_ORIGIN',
        permission: 'unavailable', subscribed: false});
      try {
        const worker = await bounded(registration());
        const subscription = worker ? await bounded(worker.pushManager.getSubscription()) : null;
        return encode({supported: true, permission: Notification.permission,
          subscribed: subscription !== null});
      } catch (error) { return failure(error); }
    },

    async activate(publicKey) {
      if (!supported()) return encode({error: 'UNSUPPORTED'});
      if (activeAttempt || pendingSubscription) return encode({error: 'PUSH_PENDING'});
      const attempt = beginAttempt();
      activeAttempt = attempt;
      try {
        const key = applicationKey(publicKey);
        // This is deliberately the first asynchronous call after the user's
        // click. Loading the card/status never requests a browser permission.
        const permission = Notification.permission === 'granted' ? 'granted' :
          await attempt.step(requestPermission);
        if (permission !== 'granted') return encode({error:
          permission === 'denied' ? 'PERMISSION_DENIED' : 'PERMISSION_DISMISSED'});
        const worker = await attempt.step(activeRegistration);
        let subscription = await attempt.step(() => worker.pushManager.getSubscription());
        const previousKey = subscription && subscription.options.applicationServerKey;
        if (subscription && previousKey &&
            (previousKey.byteLength !== key.byteLength ||
             !new Uint8Array(previousKey).every((byte, index) => byte === key[index]))) {
          const removed = await attempt.step(() => subscription.unsubscribe());
          if (!removed) throw new Error('PUSH_UNAVAILABLE');
          subscription = null;
        }
        subscription = subscription || await attempt.step(() => subscribe(worker, key, attempt));
        // Returned only to the authenticated Dart caller, never persisted here.
        return encode({token: JSON.stringify(subscription.toJSON())});
      } catch (error) { return failure(error); }
      finally {
        clearTimeout(attempt.timer);
        if (activeAttempt === attempt) activeAttempt = null;
      }
    },

    cancelActivation,

    async deactivate() {
      cancelActivation();
      if (!supported()) return encode({unsubscribed: true});
      try {
        const worker = await bounded(registration());
        const subscription = worker ? await bounded(worker.pushManager.getSubscription()) : null;
        if (subscription && !await bounded(subscription.unsubscribe())) {
          return encode({error: 'PUSH_UNAVAILABLE'});
        }
        return encode({unsubscribed: true});
      } catch (error) { return failure(error); }
    }
  });
})();
