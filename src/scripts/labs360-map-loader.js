/**
 * Charge MapKit seulement lorsque la carte approche du viewport.
 * Le cache de promesse empêche les injections concurrentes du script Apple.
 */
let loaderPromise = null;

export function loadMapKit({
  documentRef = globalThis.document,
  windowRef = globalThis.window,
  timeoutMs = 8000,
} = {}) {
  if (windowRef?.mapkit) return Promise.resolve(windowRef.mapkit);
  if (loaderPromise) return loaderPromise;

  loaderPromise = new Promise((resolve, reject) => {
    const existing = documentRef.querySelector('script[data-mapkit-loader]');
    const script = existing ?? documentRef.createElement('script');
    let settled = false;

    const finish = (error) => {
      if (settled) return;
      settled = true;
      clearTimeout(timeout);
      if (error || !windowRef?.mapkit) {
        loaderPromise = null;
        reject(error ?? new Error('MapKit indisponible'));
        return;
      }
      resolve(windowRef.mapkit);
    };

    script.addEventListener('load', () => finish(), { once: true });
    script.addEventListener(
      'error',
      () => finish(new Error('Chargement MapKit impossible')),
      { once: true },
    );

    const timeout = setTimeout(
      () => finish(new Error('MapKit indisponible après le délai maximal')),
      timeoutMs,
    );

    if (!existing) {
      script.src = 'https://cdn.apple-mapkit.com/mk/5.x.x/mapkit.js';
      script.crossOrigin = 'anonymous';
      script.dataset.mapkitLoader = '';
      documentRef.head.append(script);
    }
  });

  return loaderPromise;
}

export function observeMap(
  element,
  callback,
  IntersectionObserverClass = globalThis.IntersectionObserver,
) {
  if (!IntersectionObserverClass) {
    callback();
    return { disconnect() {} };
  }

  let activated = false;
  const observer = new IntersectionObserverClass(
    (entries) => {
      if (activated || !entries.some((entry) => entry.isIntersecting)) return;
      activated = true;
      observer.disconnect();
      callback();
    },
    { rootMargin: '500px 0px', threshold: 0 },
  );
  observer.observe(element);
  return observer;
}

export function resetMapKitLoaderForTests() {
  loaderPromise = null;
}
