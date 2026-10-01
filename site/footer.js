import { mountMarquee } from "./vendor/ap.cx-gl-marquee-0.1.0/dist/index.js";

const footerMarquee = document.querySelector(".apcx-footer-marquee");

if (footerMarquee) {
  mountMarquee(footerMarquee, {
    message: "Another Planet Creative eXperience",
    mode: "footer-banner",
    fontWeight: 400,
    appearance: { background: "#f7f7f9", text: "#171719" },
  });
}
