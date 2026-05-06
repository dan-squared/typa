<script setup>
import { ref, onMounted, nextTick } from 'vue'
import gsap from 'gsap'

const isLoading = ref(true)
const showContent = ref(false)
const displayedText = ref('')
const customCursor = ref(null)

const word = 'Typa'
const letters = word.split('')

onMounted(() => {
  const xTo = gsap.quickTo(customCursor.value, "x", { duration: 0.3, ease: "power3" })
  const yTo = gsap.quickTo(customCursor.value, "y", { duration: 0.3, ease: "power3" })

  window.addEventListener('mousemove', (e) => {
    xTo(e.clientX)
    yTo(e.clientY)
  })

  const tl = gsap.timeline()
  tl.to({}, { duration: 0.5 })

  letters.forEach((char, i) => {
    const typingDelay = i === 0 ? 0 : gsap.utils.random(0.15, 0.4)
    tl.call(() => { displayedText.value += char }, [], `+=${typingDelay}`)
  })

  tl.to({}, { duration: 1.0 })

  tl.to('.loading-screen', {
    opacity: 0,
    duration: 1.0,
    ease: 'power2.inOut',
    onComplete: () => {
      isLoading.value = false
      showContent.value = true
      nextTick(() => {
        const reveal = gsap.timeline({ defaults: { ease: 'power3.out', force3D: true } })

        // Gallery cards cascade in from the left
        reveal.fromTo('.gallery-item',
          { y: 60, opacity: 0, scale: 0.96 },
          { y: 0, opacity: 1, scale: 1, duration: 1, stagger: 0.12 }
        )

        // Bottom left info slides up while gallery is still finishing
        reveal.fromTo('.bottom-left > *',
          { y: 30, opacity: 0 },
          { y: 0, opacity: 1, duration: 0.7, stagger: 0.06 },
          '-=0.5'
        )

        // Social links fade in last
        reveal.fromTo('.bottom-right > *',
          { y: 20, opacity: 0 },
          { y: 0, opacity: 1, duration: 0.5, stagger: 0.05 },
          '-=0.3'
        )
      })
    }
  })
})
</script>

<template>
  <!-- Custom Cursor -->
  <div ref="customCursor" class="custom-cursor" :style="{ opacity: isLoading ? 0 : 1, transition: 'opacity 0.5s ease' }"></div>

  <!-- Loading -->
  <div v-if="isLoading" class="loading-screen">
    <div class="loader-content">
      <span class="loader-text">{{ displayedText }}</span>
      <span class="loader-cursor"></span>
    </div>
  </div>

  <!-- Main -->
  <div v-if="showContent" class="page">

    <!-- Gallery: horizontal showcase -->
    <section class="gallery">
      <div class="gallery-item hero-shot">
        <!-- Replace with <img src="..." /> or <video> -->
      </div>
      <div class="gallery-item side-shot">
        <!-- Replace with <img src="..." /> or <video> -->
      </div>
      <div class="gallery-item side-shot">
        <!-- Replace with <img src="..." /> or <video> -->
      </div>
    </section>

    <!-- Bottom section: info + links -->
    <section class="bottom-section">
      <div class="bottom-left">
        <div class="logo">
          <img src="./assets/typa dark.png" alt="Typa Icon" class="logo-icon" />
          Typa<span class="logo-cursor"></span>
        </div>

        <p class="description">
          A fast and lightweight typing<br/>
          practice app built natively for<br/>
          macOS. Open source, forever.
        </p>

        <div class="cta-row">
          <a href="./Typa.dmg" class="download-btn">
            <svg width="14" height="14" viewBox="0 0 549.875 549.876" fill="currentColor">
              <path d="M340.535,104.42c13.881-13.874,24.125-29.07,30.735-45.594c6.389-16.524,9.584-31.5,9.584-44.945c0-0.875-0.056-1.989-0.166-3.305c-0.116-1.316-0.165-2.411-0.165-3.305c-0.22-0.661-0.495-1.873-0.826-3.642c-0.33-1.756-0.605-2.968-0.826-3.629c-38.776,9.033-66.311,25.337-82.613,48.911c-16.524,23.789-25.117,52.1-25.778,84.927c14.755-1.328,26.211-3.188,34.37-5.612C316.747,124.249,328.638,116.323,340.535,104.42z"/>
              <path d="M452.892,359.868c-15.202-21.799-22.803-46.365-22.803-73.696c0-24.891,7.154-47.688,21.48-68.404c7.712-11.23,20.27-24.229,37.675-38.997c-11.456-14.094-22.913-25.104-34.369-33.048c-20.711-14.303-44.175-21.481-70.387-21.481c-15.643,0-34.7,3.758-57.173,11.243c-21.592,7.497-37.344,11.23-47.253,11.23c-7.49,0-22.692-3.305-45.606-9.914c-23.133-6.61-42.625-9.915-58.489-9.915c-37.895,0-69.18,15.863-93.85,47.595c-24.896,32.167-37.344,73.36-37.344,123.587c0,53.312,16.193,108.716,48.581,166.226c32.822,57.057,65.979,85.582,99.468,85.582c11.236,0,25.771-3.745,43.617-11.23c17.846-7.271,33.482-10.905,46.922-10.905c14.321,0,30.949,3.525,49.902,10.569c20.043,7.05,35.466,10.569,46.262,10.569c28.194,0,56.506-21.586,84.927-64.762c18.507-27.534,32.057-55.08,40.649-82.614C485.494,395.561,468.094,381.68,452.892,359.868z"/>
            </svg>
            Download for MacOS
          </a>
          <span class="version-tag">v0.1.0</span>
        </div>
      </div>

      <div class="bottom-right">
        <a href="https://github.com" target="_blank" class="social-link">GitHub</a>
        <a href="#" class="social-link">X</a>
      </div>
    </section>

  </div>
</template>

<style scoped>
/* ─── Cursor ─── */
.custom-cursor {
  position: fixed;
  top: 0;
  left: 0;
  width: 12px;
  height: 12px;
  background-color: #000000;
  border-radius: 3px;
  pointer-events: none;
  z-index: 9999;
  transform: translate(-50%, -50%);
  will-change: transform;
}

:global(*) {
  cursor: none !important;
}

.gallery-item, .bottom-left > *, .bottom-right > * {
  opacity: 0;
  will-change: transform, opacity;
}

/* ─── Loading ─── */
.loading-screen {
  position: fixed;
  inset: 0;
  z-index: 999;
  background-color: var(--bg-color);
  display: flex;
  align-items: center;
  justify-content: center;
}

.loader-content {
  display: flex;
  align-items: baseline;
}

.loader-text {
  font-family: 'Geist Pixel Line', monospace;
  font-size: 48px;
  font-weight: 500;
  letter-spacing: -0.04em;
  color: var(--text-primary);
}

.loader-cursor {
  display: inline-block;
  width: 3px;
  height: 39px; /* Match the font size exactly */
  background-color: var(--text-primary);
  margin-left: 6px;
  animation: cursor-blink 1s step-end infinite;
  transform: translateY(4px); /* Align slightly down with the baseline */
}

@keyframes cursor-blink {
  0%, 100% { opacity: 1; }
  50% { opacity: 0; }
}

/* ─── Page ─── */
.page {
  min-height: 100vh;
  display: flex;
  flex-direction: column;
  padding: 24px;
  gap: 24px;
}

/* ─── Gallery ─── */
.gallery {
  display: flex;
  gap: 16px;
  flex: 1;
  min-height: 0;
  overflow: hidden;
}

.gallery-item {
  background-color: var(--card-bg);
  border-radius: 16px;
  flex-shrink: 0;
  overflow: hidden;
  position: relative;
}

.gallery-item.hero-shot {
  flex: 1 1 55%;
  min-height: 520px;
}

.gallery-item.side-shot {
  flex: 1 1 20%;
  min-height: 520px;
}

.gallery-item img,
.gallery-item video {
  width: 100%;
  height: 100%;
  object-fit: cover;
  display: block;
}

/* ─── Bottom Section ─── */
.bottom-section {
  display: flex;
  justify-content: space-between;
  align-items: flex-end;
  padding: 32px 16px 16px;
  gap: 40px;
}

.bottom-left {
  display: flex;
  flex-direction: column;
  gap: 16px;
  max-width: 380px;
}

.logo {
  font-family: 'Geist Pixel Line', monospace;
  font-size: 32px;
  font-weight: 500;
  letter-spacing: -0.04em;
  color: var(--text-primary);
  display: inline-flex;
  align-items: center;
  gap: 10px;
}

.logo-icon {
  height: 0.85em;
  width: auto;
  border-radius: 6px;
}

.logo-cursor {
  display: inline-block;
  width: 3px;
  height: 0.85em;
  background-color: var(--text-primary);
  margin-left: 2px;
  animation: cursor-blink 1s step-end infinite;
}

@keyframes cursor-blink {
  0%, 100% { opacity: 1; }
  50% { opacity: 0; }
}

.description {
  font-size: 16px;
  line-height: 1.6;
  color: var(--text-secondary);
}

/* ─── CTA ─── */
.cta-row {
  display: flex;
  align-items: center;
  gap: 12px;
  margin-top: 4px;
}

.download-btn {
  display: inline-flex;
  align-items: center;
  gap: 10px;
  padding: 13px 24px;
  border-radius: 10px;
  font-size: 14px;
  font-weight: 600;
  background-color: var(--text-primary);
  color: var(--bg-color);
  transition: opacity 0.2s;
  letter-spacing: -0.01em;
}

.download-btn:hover {
  opacity: 0.85;
}

.version-tag {
  font-size: 13px;
  font-weight: 500;
  color: var(--text-secondary);
  padding: 5px 12px;
  border: 1px solid var(--border-color);
  border-radius: 100px;
}

/* ─── Links ─── */
.bottom-right {
  display: flex;
  gap: 24px;
  align-items: flex-end;
}

.social-link {
  font-size: 15px;
  font-weight: 500;
  color: var(--text-secondary);
  transition: color 0.2s;
}

.social-link:hover {
  color: var(--text-primary);
}

/* ─── Responsive ─── */
@media (max-width: 1024px) {
  .page {
    height: 100dvh;
    overflow: hidden;
  }

  .gallery {
    overflow-x: auto;
    scroll-snap-type: x mandatory;
    -ms-overflow-style: none;
    scrollbar-width: none;
  }
  
  .gallery::-webkit-scrollbar {
    display: none;
  }

  .gallery-item.hero-shot,
  .gallery-item.side-shot {
    flex: 0 0 85%;
    min-height: 320px;
    scroll-snap-align: center;
  }

  .bottom-section {
    flex-direction: column;
    align-items: flex-start;
    gap: 24px;
    flex-shrink: 0;
  }
}

@media (max-width: 640px) {
  .page {
    padding: 16px;
    gap: 16px;
  }

  .gallery-item.hero-shot,
  .gallery-item.side-shot {
    flex: 0 0 90%;
    min-height: 100%; /* Fill available height */
  }

  .gallery {
    gap: 12px;
  }

  .bottom-section {
    gap: 24px;
  }

  .bottom-right {
    width: 100%;
    justify-content: flex-end;
  }

  .logo {
    font-size: 24px;
  }

  .description {
    font-size: 14px;
  }
}
</style>
