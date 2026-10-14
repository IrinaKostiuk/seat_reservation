import { Socket } from "/vendor/phoenix/phoenix.mjs";
import { LiveSocket } from "/vendor/live-view/phoenix_live_view.esm.js";

const csrfToken = document.querySelector('meta[name="csrf-token"]').content;
const liveSocket = new LiveSocket("/live", Socket, {
  params: { _csrf_token: csrfToken },
});
liveSocket.connect();
