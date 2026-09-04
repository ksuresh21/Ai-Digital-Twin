/* Soraya's browser front end.
 *
 * No framework, no build step, no CDN. One file, and it is the whole client:
 * the sprite animator, the streaming reader, the settings form, and the
 * microphone.
 *
 * Two things worth knowing before editing:
 *
 * 1. Speech recognition runs *here*, in the browser, using the Web Speech API.
 *    That is not a shortcut -- it means no Whisper install, no audio upload,
 *    and nothing leaves the machine to be transcribed. It also means it only
 *    works where the browser supports it (Chrome and Edge do; Safari's support
 *    is unreliable), which the UI says out loud rather than failing silently.
 *
 * 2. Her reply arrives as server-sent events over a POST, read with a stream
 *    reader rather than EventSource -- EventSource is GET-only.
 */

const $ = (id) => document.getElementById(id);

const state = {
  clips: {},          // clip name -> [frame urls]
  frame: 0,
  clip: "idle",
  timer: null,
  settings: null,
  listening: false,
  busy: false,
  shownWarning: null,
};

/* ---------------------------------------------------------------- sprite */

const FRAME_MS = 130;

function playClip(name) {
  const frames = state.clips[name] || state.clips.idle;
  if (!frames || !frames.length) {
    $("sprite").hidden = true;
    $("sprite-empty").hidden = false;
    $("clip-name").textContent = name;
    return;
  }
  $("sprite-empty").hidden = true;
  $("sprite").hidden = false;
  state.clip = name;
  state.frame = 0;
  $("clip-name").textContent = name;

  clearInterval(state.timer);
  const step = () => {
    $("sprite").src = "/art/" + frames[state.frame % frames.length];
    state.frame += 1;
  };
  step();
  if (frames.length > 1) state.timer = setInterval(step, FRAME_MS);
}

/* ------------------------------------------------------------------- log */

function bubble(kind, text) {
  const node = document.createElement("div");
  node.className = "bubble " + kind;
  node.textContent = text;
  $("log").appendChild(node);
  $("log").scrollTop = $("log").scrollHeight;
  return node;
}

/* ---------------------------------------------------------------- mood */

function showAffect(a) {
  $("mood-label").textContent = a.label || "—";
  $("mood-posture").textContent = a.posture || a.label || "—";
  // Valence is -1..1; the meter is a width, so map it onto 0..100.
  $("meter-valence").style.width = (((a.valence ?? 0) + 1) / 2 * 100) + "%";
  $("meter-arousal").style.width = ((a.arousal ?? 0.3) * 100) + "%";
  const why = (a.evidence || []).join(", ");
  const sure = a.confidence != null ? Math.round(a.confidence * 100) : null;
  $("mood-why").textContent = why
    ? `heard: ${why}${sure !== null ? ` · ${sure}% sure` : ""}`
    : "";
}

/* --------------------------------------------------------------- turns */

/** Reads an SSE stream from a POST and dispatches each event. */
async function streamTurn(url, body) {
  if (state.busy) return;
  state.busy = true;
  $("send").disabled = true;

  let herBubble = null;
  let thinking = bubble("her thinking", "…");

  try {
    const response = await fetch(url, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(body || {}),
    });
    if (!response.ok || !response.body) {
      throw new Error(`server said ${response.status}`);
    }

    const reader = response.body.getReader();
    const decoder = new TextDecoder();
    let buffer = "";

    while (true) {
      const { value, done } = await reader.read();
      if (done) break;
      buffer += decoder.decode(value, { stream: true });

      // Events are separated by a blank line. Anything after the last one is
      // a partial frame and stays in the buffer.
      const frames = buffer.split("\n\n");
      buffer = frames.pop() ?? "";

      for (const frame of frames) {
        const line = frame.split("\n").find((l) => l.startsWith("data:"));
        if (!line) continue;
        let event;
        try { event = JSON.parse(line.slice(5).trim()); } catch { continue; }

        if (event.type === "pose") {
          playClip(event.clip);
        } else if (event.type === "affect") {
          showAffect(event);
        } else if (event.type === "chunk") {
          if (thinking) { thinking.remove(); thinking = null; }
          if (!herBubble) herBubble = bubble("her", "");
          herBubble.textContent += event.text;
          $("log").scrollTop = $("log").scrollHeight;
        } else if (event.type === "done") {
          if (event.spoke) $("voice-chip").classList.add("live");
        } else if (event.type === "error") {
          if (thinking) { thinking.remove(); thinking = null; }
          bubble("error", event.message);
        }
      }
    }
  } catch (err) {
    bubble("error", `Could not reach her: ${err.message}`);
  } finally {
    if (thinking) thinking.remove();
    state.busy = false;
    $("send").disabled = false;
    // Ask her, after the fact, whether anything was worth remembering. Fired
    // and forgotten -- it must never make the next message wait.
    fetch("/api/remember", { method: "POST", headers: { "Content-Type": "application/json" }, body: "{}" })
      .then((r) => r.json())
      .then((d) => { if (d.kept?.length) bubble("note", "remembered: " + d.kept.join(" · ")); })
      .catch(() => {});
  }
}

function send() {
  const text = $("input").value.trim();
  if (!text || state.busy) return;
  bubble("them", text);
  $("input").value = "";
  $("input").style.height = "auto";
  streamTurn("/api/say", { message: text });
}

async function lookUp() {
  const text = $("input").value.trim();
  if (!text || state.busy) return;
  bubble("them", text);
  $("input").value = "";
  state.busy = true;
  $("look-up").disabled = true;
  playClip("thinking");
  const waiting = bubble("her thinking", "looking…");
  try {
    const response = await fetch("/api/research", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ question: text }),
    });
    const data = await response.json();
    waiting.remove();
    if (data.error) {
      bubble("error", data.error);
    } else {
      const node = bubble("her", data.text || "(nothing came back)");
      if (data.findings?.length) {
        const sources = document.createElement("div");
        sources.className = "sources";
        sources.innerHTML = data.findings.slice(0, 6).map(
          (f) => `<a href="${f.url}" target="_blank" rel="noopener noreferrer">${
            (f.title || f.url).replace(/</g, "&lt;")}</a>`
        ).join(" · ");
        node.appendChild(sources);
      }
    }
  } catch (err) {
    waiting.remove();
    bubble("error", `The search did not come back: ${err.message}`);
  } finally {
    state.busy = false;
    $("look-up").disabled = false;
    playClip("idle");
  }
}

/* ----------------------------------------------------------- microphone */

let recognition = null;

function speechSupport() {
  return window.SpeechRecognition || window.webkitSpeechRecognition || null;
}

function setupMic() {
  const Impl = speechSupport();
  if (!Impl) {
    $("mic").disabled = true;
    $("mic").title = "This browser has no speech recognition — try Chrome";
    $("ears-warning").textContent =
      "This browser cannot do speech recognition. Chrome and Edge can; " +
      "Safari is unreliable. Typing works everywhere.";
    return;
  }
  recognition = new Impl();
  recognition.continuous = true;
  recognition.interimResults = true;
  recognition.lang = "en-GB";

  recognition.onresult = (event) => {
    let interim = "", finalText = "";
    for (let i = event.resultIndex; i < event.results.length; i += 1) {
      const chunk = event.results[i][0].transcript;
      if (event.results[i].isFinal) finalText += chunk;
      else interim += chunk;
    }
    const heard = (finalText || interim).trim();
    if (heard) {
      $("heard-chip").hidden = false;
      $("heard-chip").textContent = "heard: " + heard.slice(-48);
    }
    if (!finalText.trim()) return;

    // The wake phrase is matched on the server, because that is where the
    // fuzzy matching and the configured phrases live -- and duplicating that
    // logic in two languages is how the two drift apart.
    fetch("/api/wake", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ heard: finalText }),
    })
      .then((r) => r.json())
      .then((match) => {
        if (!match.hit) return;
        const said = match.remainder || "(they said your name)";
        bubble("them", finalText.trim());
        streamTurn("/api/say", { message: said });
      })
      .catch(() => {});
  };

  recognition.onerror = (event) => {
    if (event.error === "not-allowed") {
      $("ears-warning").textContent =
        "The browser blocked the microphone. Allow it in the address bar.";
      stopMic();
    }
  };
  // continuous mode still stops on its own after a pause; restart while the
  // user believes it is on, or the mic silently dies after one sentence.
  recognition.onend = () => { if (state.listening) { try { recognition.start(); } catch {} } };
}

function startMic() {
  if (!recognition) return;
  try { recognition.start(); } catch { /* already running */ }
  state.listening = true;
  $("mic").classList.add("on");
  $("heard-chip").hidden = false;
  $("heard-chip").textContent = "listening…";
}

function stopMic() {
  state.listening = false;
  $("mic").classList.remove("on");
  $("heard-chip").hidden = true;
  if (recognition) { try { recognition.stop(); } catch {} }
}

/* -------------------------------------------------------------- settings */

async function patch(partial) {
  const response = await fetch("/api/settings", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(partial),
  });
  applyState(await response.json());
}

function applyState(data) {
  state.settings = data.settings;
  state.clips = data.sprite.clips || {};
  const s = data.settings;

  $("her-name").textContent = s.name;
  // Pack as well as brain: with packs coming from two roots it is worth
  // being able to see at a glance which character is actually loaded.
  $("brain-line").textContent = [
    data.sprite.pack,
    data.brain.name + (data.brain.model ? " " + data.brain.model : ""),
  ].join(" · ");

  // Voice
  $("voice-enabled").checked = s.voice.enabled;
  $("voice-rate").value = s.voice.rate;
  $("voice-volume").value = s.voice.volume;
  $("quiet-hours").checked = s.quiet_hours.enabled;
  const picker = $("voice-name");
  if (!picker.dataset.filled) {
    picker.innerHTML =
      `<option value="">System default</option>` +
      (data.voice.voices || []).map((v) => {
        const name = v.split("|")[0];
        return `<option value="${name}">${name}</option>`;
      }).join("");
    picker.dataset.filled = "1";
  }
  picker.value = s.voice.name || "";
  $("voice-chip").textContent = s.voice.enabled ? "voice on" : "voice off";
  $("voice-chip").classList.toggle("live", s.voice.enabled);
  if (!data.voice.available) {
    $("voice-enabled").disabled = true;
    $("voice-enabled").title = "No `say` command found — macOS only";
  }

  // Ears
  $("ears-enabled").checked = s.ears.enabled;
  $("wake-phrases").value = (s.ears.wake_phrases || []).join(", ");

  // Mind
  $("brain-provider").value = s.brain.provider;
  $("brain-model").value = s.brain.model;
  $("brain-base-url").value = s.brain.base_url;
  $("brain-effort").value = s.brain.effort;

  // Presence
  $("initiative").value = s.presence.initiative;
  $("min-gap").value = s.presence.min_minutes_between_approaches;
  $("greet-unlock").checked = s.presence.greet_on_unlock;

  // You
  $("user-name").value = s.user_name || "";
  const packs = $("pack");
  packs.innerHTML = (data.sprite.packs || []).map(
    (p) => `<option${p === s.character_pack ? " selected" : ""}>${p}</option>`
  ).join("");

  // Say what is actually playing, not just what is absent. "No Thinking
  // frames" leaves you wondering what you are looking at; "Thinking → Focus"
  // tells you, and tells you the pack is being used well.
  const swaps = Object.entries(data.sprite.substitutions || {});
  $("pack-warning").textContent = swaps.length
    ? `${data.sprite.pack} has no frames for ${swaps.length} clip${
        swaps.length === 1 ? "" : "s"}, so it uses the nearest pose: ${
        swaps.map(([want, got]) => `${want} → ${got}`).join(", ")}.`
    : "";

  // Once per distinct message. applyState runs after every settings change,
  // so without this a bad API key stacked an identical error bubble each time
  // you nudged the volume slider.
  if (data.brain.warning && data.brain.warning !== state.shownWarning) {
    state.shownWarning = data.brain.warning;
    bubble("error", data.brain.warning);
  }
  if (data.affect) showAffect(data.affect);
  playClip(state.clip in state.clips ? state.clip : "idle");
}

/* ------------------------------------------------------------------ wire */

function wire() {
  $("send").onclick = send;
  $("look-up").onclick = lookUp;
  $("come-over").onclick = () => streamTurn("/api/approach", { force: true });

  $("input").addEventListener("keydown", (event) => {
    // Enter sends; shift-enter is a newline. Standard for a chat box, and the
    // opposite arrangement annoys everyone.
    if (event.key === "Enter" && !event.shiftKey) {
      event.preventDefault();
      send();
    }
  });
  $("input").addEventListener("input", (event) => {
    event.target.style.height = "auto";
    event.target.style.height = Math.min(132, event.target.scrollHeight) + "px";
    // She stops talking the moment you start typing.
    fetch("/api/stop-voice", { method: "POST" }).catch(() => {});
  });

  $("mic").onclick = () => (state.listening ? stopMic() : startMic());

  $("voice-enabled").onchange = (e) => patch({ voice: { enabled: e.target.checked } });
  $("voice-name").onchange = (e) => patch({ voice: { name: e.target.value } });
  $("voice-rate").onchange = (e) => patch({ voice: { rate: +e.target.value } });
  $("voice-volume").onchange = (e) => patch({ voice: { volume: +e.target.value } });
  $("quiet-hours").onchange = (e) => patch({ quiet_hours: { enabled: e.target.checked } });

  $("ears-enabled").onchange = (e) => {
    patch({ ears: { enabled: e.target.checked } });
    e.target.checked ? startMic() : stopMic();
  };
  $("wake-phrases").onchange = (e) => patch({
    ears: { wake_phrases: e.target.value.split(",").map((p) => p.trim()).filter(Boolean) },
  });

  $("brain-provider").onchange = (e) => patch({ brain: { provider: e.target.value } });
  $("brain-model").onchange = (e) => patch({ brain: { model: e.target.value } });
  $("brain-base-url").onchange = (e) => patch({ brain: { base_url: e.target.value } });
  $("brain-effort").onchange = (e) => patch({ brain: { effort: e.target.value } });

  $("initiative").onchange = (e) => patch({ presence: { initiative: e.target.value } });
  $("min-gap").onchange = (e) => patch({
    presence: { min_minutes_between_approaches: +e.target.value },
  });
  $("greet-unlock").onchange = (e) => patch({ presence: { greet_on_unlock: e.target.checked } });

  $("user-name").onchange = (e) => patch({ user_name: e.target.value });
  $("pack").onchange = (e) => patch({ character_pack: e.target.value });

  $("show-notes").onclick = async () => {
    const data = await (await fetch("/api/notes")).json();
    bubble("note", data.notes.length
      ? data.notes.map((n) => `${n.kind}: ${n.text}`).join("\n")
      : "She hasn't written anything down yet.");
  };
  $("forget").onclick = async () => {
    if (!confirm("Delete every conversation and everything she remembers? This cannot be undone.")) return;
    await fetch("/api/forget", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ confirm: "yes" }),
    });
    $("log").innerHTML = "";
    bubble("note", "Forgotten. Starting over.");
  };
}

/* ------------------------------------------------------------------ boot */

(async function boot() {
  wire();
  setupMic();
  try {
    applyState(await (await fetch("/api/state")).json());
    if (state.settings?.ears?.enabled) startMic();
  } catch (err) {
    bubble("error", "Could not load her state. Is the server running?");
  }
})();
