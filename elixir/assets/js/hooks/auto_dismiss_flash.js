// Auto-dismiss flash hook
export const AutoDismissFlash = {
  mounted() {
    this.startAutoDismiss();
  },
  
  startAutoDismiss() {
    const progressBar = this.el.querySelector('.progress-bar');
    if (!progressBar) return;
    
    // Get the flash kind from the element ID (flash-info, flash-error)
    const flashKind = this.el.id.replace('flash-', '');
    
    // Start the progress bar animation
    let progress = 100;
    const duration = 3000; // 3 seconds
    const interval = 50; // Update every 50ms
    const decrement = (100 / duration) * interval;
    
    const timer = setInterval(() => {
      progress -= decrement;
      
      if (progress <= 0) {
        clearInterval(timer);
        progressBar.style.width = '0%';
        // Add a longer delay to ensure the progress bar animation completes visually
        setTimeout(() => {
          this.pushEvent('lv:clear-flash', {key: flashKind});
        }, 300); // 300ms delay for visual completion
      } else {
        progressBar.style.width = progress + '%';
      }
    }, interval);
    
    // Store timer reference for cleanup
    this.timer = timer;
  },
  
  destroyed() {
    if (this.timer) {
      clearInterval(this.timer);
    }
  }
};