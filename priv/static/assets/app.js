// Connects the page to its LiveView process (one per tab; that process is the
// fan) and animates the countdown of each hold between server updates.

const Countdown = {
  mounted() {
    this.start()
  },
  updated() {
    this.start()
  },
  destroyed() {
    cancelAnimationFrame(this.frame)
  },
  start() {
    cancelAnimationFrame(this.frame)
    const total = Number(this.el.dataset.total)
    const end = performance.now() + Number(this.el.dataset.remaining)
    const fill = this.el.querySelector("[data-fill]")
    const seconds = this.el.querySelector("[data-seconds]")

    const tick = () => {
      const left = Math.max(0, end - performance.now())
      fill.style.transform = `scaleX(${left / total})`
      seconds.textContent = `${Math.ceil(left / 1000)}s`
      if (left > 0) this.frame = requestAnimationFrame(tick)
    }

    tick()
  },
}

const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")

const liveSocket = new LiveView.LiveSocket("/live", Phoenix.Socket, {
  params: { _csrf_token: csrfToken },
  hooks: { Countdown },
})

liveSocket.connect()
