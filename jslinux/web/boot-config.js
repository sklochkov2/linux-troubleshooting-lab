(function () {
  "use strict";

  var params = new URLSearchParams(window.location.search);
  var scenarios = {
    endpoint1: { family: "system", number: 1, category: "System" },
    endpoint2: { family: "system", number: 2, category: "System" },
    endpoint3: { family: "system", number: 3, category: "System" },
    endpoint4: { family: "system", number: 4, category: "System" },
    database1: { family: "database", number: 1, category: "Database" }
  };
  var scenario = params.get("scenario") || "endpoint1";
  var metadata;
  var imageUrl;
  var selectedVersion;
  var versionScript = document.querySelector(
    'script[src^="image-versions-"]'
  );

  if (!Object.prototype.hasOwnProperty.call(scenarios, scenario)) {
    scenario = "endpoint1";
  }
  metadata = scenarios[scenario];
  selectedVersion = window.LAB_IMAGE_VERSIONS &&
    window.LAB_IMAGE_VERSIONS[metadata.family];

  console.group("[JSLinux boot] configuration");
  console.log("Page URL before configuration:", window.location.href);
  console.log("Boot script URL:", document.currentScript && document.currentScript.src);
  console.log(
    "Image-version script URL:",
    versionScript && versionScript.src
  );
  console.log("Image-version manifest:", window.LAB_IMAGE_VERSIONS);
  console.log("Requested scenario:", params.get("scenario"));
  console.log("Selected scenario:", scenario);
  console.log("Scenario metadata:", metadata);
  console.log("Selected image version:", selectedVersion);

  if (!selectedVersion) {
    console.error(
      "No image version is defined for family:",
      metadata.family
    );
  }

  if (metadata.family === "database") {
    imageUrl =
      "root-x86_64-database-" +
      selectedVersion +
      ".cfg";
  } else {
    imageUrl = "root-x86_64-" + selectedVersion + ".cfg";
  }
  console.log("Resolved image configuration:", imageUrl);

  window.LAB_SCENARIO = scenario;
  window.LAB_SCENARIO_META = metadata;

  params.set("scenario", scenario);
  params.set("cpu", "x86_64");
  params.set("url", imageUrl);
  params.set("mem", "512");
  params.set("cmdline", "LAB_SCENARIO=" + scenario);

  window.history.replaceState(
    null,
    "",
    window.location.pathname + "?" + params.toString() + window.location.hash
  );
  console.log("Page URL after configuration:", window.location.href);
  console.groupEnd();
})();
