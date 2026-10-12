const comparison = document.querySelector(".compare");
const comparisonSlider = document.querySelector(".compare-slider");

if (comparison && comparisonSlider) {
  comparisonSlider.addEventListener("input", () => {
    comparison.style.setProperty("--split", `${comparisonSlider.value}%`);
  });
}

document.querySelectorAll(".view-toggle").forEach((toggle) => {
  toggle.addEventListener("click", (event) => {
    const button = event.target.closest("button[data-mode]");
    if (!button) return;
    const media = toggle.closest(".example-card").querySelector(".example-media");
    media.dataset.view = button.dataset.mode;
    toggle.querySelectorAll("button").forEach((item) => {
      item.classList.toggle("is-active", item === button);
    });
  });
});

document.querySelector(".filter-bar")?.addEventListener("click", (event) => {
  const button = event.target.closest("button[data-filter]");
  if (!button) return;
  const filter = button.dataset.filter;
  document.querySelectorAll(".filter-button").forEach((item) => {
    const active = item === button;
    item.classList.toggle("is-active", active);
    item.setAttribute("aria-pressed", String(active));
  });
  document.querySelectorAll(".example-card").forEach((card) => {
    card.hidden = filter !== "all" && card.dataset.category !== filter;
  });
});

document.querySelector("[data-copy]")?.addEventListener("click", async (event) => {
  const button = event.currentTarget;
  const command = button.previousElementSibling.textContent;
  try {
    await navigator.clipboard.writeText(command);
    button.textContent = "Copied";
    window.setTimeout(() => { button.textContent = "Copy"; }, 1600);
  } catch {
    button.textContent = "Select";
    window.getSelection()?.selectAllChildren(button.previousElementSibling);
  }
});
