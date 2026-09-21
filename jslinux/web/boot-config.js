(function () {
  "use strict";

  var params = new URLSearchParams(window.location.search);
  var scenario = params.get("scenario") || "endpoint1";
  if (!/^endpoint[1-4]$/.test(scenario)) {
    scenario = "endpoint1";
  }
  window.LAB_SCENARIO = scenario;

  params.set("scenario", scenario);
  if (!params.has("cpu")) {
    params.set("cpu", "x86_64");
  }
  if (!params.has("url")) {
    params.set(
      "url",
      "root-x86_64-" + window.LAB_IMAGE_VERSION + ".cfg"
    );
  }
  if (!params.has("mem")) {
    params.set("mem", "512");
  }
  params.set("cmdline", "LAB_SCENARIO=" + scenario);

  window.history.replaceState(
    null,
    "",
    window.location.pathname + "?" + params.toString() + window.location.hash
  );
})();
