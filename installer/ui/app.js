(() => {
  "use strict";
  const state = { image: null, target: null, phrase: "" };
  const $ = id => document.getElementById(id);
  const invoke = async (command, args = {}) => {
    const bridge = globalThis.__TAURI__?.core?.invoke;
    if (!bridge) throw new Error("The secure installer service is not connected.");
    return bridge(command, args);
  };
  const show = step => {
    document.querySelectorAll(".panel").forEach(x => x.classList.toggle("active", x.id === step));
    const order = ["image", "drive", "write", "done"], current = order.indexOf(step);
    document.querySelectorAll(".step").forEach((x, i) => {
      x.classList.toggle("active", i === current);
      x.classList.toggle("complete", i < current);
    });
  };
  const error = message => { $("alert").textContent = message; $("alert").hidden = !message; };
  const formatBytes = value => (value / 1073741824).toFixed(1) + " GB";
  const loadDrives = async () => {
    error("");
    const targets = await invoke("list_targets");
    const eligible = targets.filter(x => x.removable && !x.system && !x.mounted && !x.read_only && x.size_bytes >= 8589934592);
    $("drives").replaceChildren(...eligible.map(target => {
      const button = document.createElement("button");
      button.className = "drive";
      button.innerHTML = '<b>▣</b><span><strong></strong><small></small></span><em>Eligible</em>';
      button.querySelector("strong").textContent = target.model;
      button.querySelector("small").textContent = target.path + " · " + formatBytes(target.size_bytes);
      button.onclick = () => selectTarget(target);
      return button;
    }));
    if (!eligible.length) $("drives").textContent = "No eligible removable drives found. Connect an 8 GB or larger drive, then refresh.";
  };
  const selectTarget = target => {
    state.target = target;
    state.phrase = "ERASE " + target.model + " — " + target.path + " — " + target.size_bytes;
    $("target-summary").textContent = target.model + " · " + target.path + " · " + formatBytes(target.size_bytes);
    $("confirmation-phrase").textContent = state.phrase;
    $("confirmation").value = "";
    $("write-button").disabled = true;
    show("write");
  };
  $("choose-image").onclick = async () => {
    try {
      error("");
      state.image = await invoke("choose_and_verify_image");
      $("image-result").textContent = "✓ Verified " + state.image.name + " · " + state.image.version;
      $("image-result").hidden = false;
      await loadDrives();
      show("drive");
    } catch (e) { error(e.message || String(e)); }
  };
  $("refresh").onclick = () => loadDrives().catch(e => error(e.message || String(e)));
  $("confirmation").oninput = event => { $("write-button").disabled = event.target.value !== state.phrase; };
  $("write-button").onclick = async () => {
    try {
      error("");
      $("write-button").disabled = true;
      $("progress").hidden = false;
      $("progress").querySelector("i").style.width = "15%";
      await invoke("write_verified_image", { image: state.image, targetId: state.target.id, confirmation: $("confirmation").value });
      $("progress").querySelector("i").style.width = "100%";
      show("done");
    } catch (e) {
      $("progress").hidden = true;
      error((e.message || e) + " The drive was not accepted as complete; rewrite it from the beginning.");
    }
  };
  $("start-over").onclick = () => { state.image = state.target = null; error(""); show("image"); };
})();
