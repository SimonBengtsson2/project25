document.addEventListener('DOMContentLoaded', () => {
    const deck = document.querySelector('.pack-result-deck');
  
    if (!deck) {
      console.error('Deck element not found!');
      return;
    }
  
    // Add the scattered class to animate the cards
    setTimeout(() => {
      deck.classList.add('is-scattered');
    }, 1);
  
    // Function to remove the top card
    const removeTopCard = () => {
      const topCard = deck.lastElementChild;
      if (topCard) {
        topCard.classList.add('is-offscreen--l');
        setTimeout(() => {
          topCard.remove();
        }, 500);
      }
    };
  
    // Click event to remove the top card
    deck.addEventListener('click', (e) => {
      e.stopPropagation();
      removeTopCard();
    });
  
    // Optional: Add a click event to the body to add a new card (for testing)
    document.body.addEventListener('click', () => {
      console.log('Body clicked');
    });
  });




  document.addEventListener('DOMContentLoaded', () => {
    const updateCardImage = (selectElement) => {
      const selectedOption = selectElement.options[selectElement.selectedIndex];
      const imageTargetId = selectElement.dataset.imageTarget;
      const imageElement = document.getElementById(imageTargetId);
  
      if (selectedOption && selectedOption.dataset.image) {
        imageElement.src = selectedOption.dataset.image; // Update the image source
      } else {
        imageElement.src = '/img/placeholder.png'; // Fallback to placeholder if no card is selected
      }
    };
  
    const selectElements = document.querySelectorAll('select[data-image-target]');
    selectElements.forEach((selectElement) => {
      selectElement.addEventListener('change', () => updateCardImage(selectElement));
    });
  });