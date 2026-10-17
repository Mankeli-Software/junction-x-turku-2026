{{flutter_js}}
{{flutter_build_config}}

// AMRight loading screen. Flutter does not report download progress, so the bar
// creeps toward a target for each startup stage and jumps ahead when the stage ends.
(function () {
  const loader = document.getElementById('amr-loader');
  const fill = document.getElementById('amr-fill');
  const bar = document.getElementById('amr-bar');
  const label = document.getElementById('amr-label');

  let shown = 0;
  let target = 0.35;

  function render() {
    const pct = Math.round(shown * 100);
    fill.style.width = pct + '%';
    bar.setAttribute('aria-valuenow', String(pct));
  }

  function stage(nextTarget, text) {
    shown = Math.max(shown, target * 0.98);
    target = nextTarget;
    if (text) label.textContent = text;
    render();
  }

  const timer = setInterval(function () {
    if (shown < target - 0.005) {
      shown += Math.max(0.002, (target - shown) * 0.04);
      render();
    }
  }, 50);

  function finish() {
    clearInterval(timer);
    shown = 1;
    render();
    label.textContent = 'Ready';
    setTimeout(function () {
      loader.classList.add('amr-done');
      setTimeout(function () { loader.remove(); }, 450);
    }, 250);
  }

  window.addEventListener('flutter-first-frame', finish, { once: true });

  _flutter.loader.load({
    onEntrypointLoaded: async function (engineInitializer) {
      stage(0.7, 'Connecting to lab data');
      const appRunner = await engineInitializer.initializeEngine();
      stage(0.95, 'Getting your home ready');
      await appRunner.runApp();
    }
  });
})();
