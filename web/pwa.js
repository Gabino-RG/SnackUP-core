'use strict';

// One application-owned worker; the Docker build disables Flutter's generated SW.
// Registration does not request notification permission or store session data.
if ('serviceWorker' in navigator && window.isSecureContext) {
  window.addEventListener('load', async () => {
    const base = new URL(document.baseURI);
    try {
      const registrations = await navigator.serviceWorker.getRegistrations();
      for (const registration of registrations) {
        if (registration.scope !== base.href) continue;
        const worker = registration.active || registration.waiting || registration.installing;
        // Replace only Flutter's old generated worker at this exact scope.
        // An unrelated messaging/custom worker must be integrated deliberately.
        if (worker && !['flutter_service_worker.js', 'snackup_service_worker.js'].includes(
          new URL(worker.scriptURL).pathname.split('/').pop())) return;
      }
      await navigator.serviceWorker.register(new URL('snackup_service_worker.js', base), {
        scope: base.pathname,
        updateViaCache: 'none',
      });
    } catch (_) {
      // A blocked worker must not prevent online application startup.
    }
  }, {once: true});
}
