(function () {
  "use strict";

  var prefix = "\x1b]777;lab-status;";
  var terminator = "\x07";
  var pending = "";
  var lastStatusAt = 0;
  var statusElement = document.getElementById("challenge-status");
  var detailElement = document.getElementById("status-detail");
  var resetButton = document.getElementById("reset-vm");
  var fileInput = document.getElementById("files");
  var consoleInput = document.getElementById("term_paste");
  var sendButton = document.getElementById("send-console");
  var sendEnterButton = document.getElementById("send-console-enter");
  var scenario = window.LAB_SCENARIO;
  var challengeNumber = scenario.slice(-1);

  document.getElementById("challenge-title").textContent =
    "Challenge " + challengeNumber;
  document.title =
    "Challenge " + challengeNumber + " · Linux troubleshooting lab";

  function setStatus(state) {
    var labels = {
      starting: "Starting VM",
      unhealthy: "Needs repair",
      healthy: "Working",
      unknown: "Status unavailable"
    };
    var details = {
      starting: "Waiting for the guest probe",
      unhealthy: "The in-guest endpoint probe is failing",
      healthy: "The in-guest endpoint probe succeeded",
      unknown: "No recent status received from the guest"
    };

    statusElement.className = "status status-" + state;
    statusElement.textContent = labels[state];
    detailElement.textContent = details[state];
  }

  function receive(payload) {
    var fields = payload.split(";");
    if (
      fields.length !== 2 ||
      fields[0] !== scenario ||
      !/^(starting|unhealthy|healthy)$/.test(fields[1])
    ) {
      return;
    }

    lastStatusAt = Date.now();
    setStatus(fields[1]);
  }

  function suffixLength(value, expectedPrefix) {
    var maximum = Math.min(value.length, expectedPrefix.length - 1);
    var length;

    for (length = maximum; length > 0; length -= 1) {
      if (value.slice(-length) === expectedPrefix.slice(0, length)) {
        return length;
      }
    }
    return 0;
  }

  function filterConsoleData(chunk, write) {
    var rendered = "";
    pending += chunk;

    while (pending.length > 0) {
      var start = pending.indexOf(prefix);
      if (start < 0) {
        var keep = suffixLength(pending, prefix);
        rendered += pending.slice(0, pending.length - keep);
        pending = pending.slice(pending.length - keep);
        break;
      }

      rendered += pending.slice(0, start);
      var finish = pending.indexOf(terminator, start + prefix.length);
      if (finish < 0) {
        pending = pending.slice(start);
        break;
      }

      receive(pending.slice(start + prefix.length, finish));
      pending = pending.slice(finish + terminator.length);
    }

    if (rendered.length > 0) {
      write(rendered);
    }
  }

  function attachConsoleFilter() {
    if (typeof term === "undefined" || !term || term.labStatusFilterAttached) {
      return false;
    }

    var originalWrite = term.write.bind(term);
    term.write = function (chunk) {
      filterConsoleData(chunk, originalWrite);
    };
    term.labStatusFilterAttached = true;
    return true;
  }

  function sendToConsole(appendEnter) {
    var text;

    if (typeof term === "undefined" || !term) {
      return;
    }
    text = consoleInput.value.replace(/\r\n?/g, "\n");
    if (!text && !appendEnter) {
      return;
    }
    if (appendEnter) {
      text += "\n";
    }
    if (term.utf8) {
      text = term.to_utf8(text);
    }
    term.queue_chars(text);
    consoleInput.value = "";
    term.term_el.focus();
  }

  var attachTimer = window.setInterval(function () {
    if (attachConsoleFilter()) {
      window.clearInterval(attachTimer);
    }
  }, 10);

  window.setInterval(function () {
    if (lastStatusAt > 0 && Date.now() - lastStatusAt > 12000) {
      setStatus("unknown");
    }
  }, 3000);

  resetButton.addEventListener("click", function () {
    resetButton.disabled = true;
    resetButton.textContent = "Resetting…";
    window.location.reload();
  });

  fileInput.addEventListener("change", function () {
    on_update_files(fileInput.files);
  });

  sendButton.addEventListener("click", function () {
    sendToConsole(false);
  });

  sendEnterButton.addEventListener("click", function () {
    sendToConsole(true);
  });

  consoleInput.addEventListener("keydown", function (event) {
    if (event.key === "Enter" && (event.ctrlKey || event.metaKey)) {
      event.preventDefault();
      sendToConsole(true);
    }
  });
})();
