/**
 * Simple Cart - Direct to API
 * Bypass localStorage, submit langsung ke database
 */

import { supabase } from './app.js';

let items = [];

export function initSimpleCart() {
  enhanceCards();
}

function enhanceCards() {
  document.addEventListener('click', async (e) => {
    // Qty controls
    if (e.target.classList.contains('simple-qty-minus')) {
      const input = e.target.closest('.simple-qty').querySelector('input');
      input.value = Math.max(1, parseInt(input.value) - 1);
    }

    if (e.target.classList.contains('simple-qty-plus')) {
      const input = e.target.closest('.simple-qty').querySelector('input');
      input.value = Math.min(999, parseInt(input.value) + 1);
    }

    // Add button
    if (e.target.classList.contains('simple-add-btn')) {
      e.preventDefault();
      const card = e.target.closest('.item-card');
      const qtyInput = card.querySelector('[data-simple-qty]');
      const qty = parseInt(qtyInput.value) || 1;

      const title = card.querySelector('h3')?.textContent || 'Item';
      const priceText = card.querySelector('b')?.textContent || '0';
      const price = parseInt(priceText.replace(/\D/g, '')) || 0;
      const image = card.querySelector('img')?.src || '';

      items.push({
        title,
        price,
        image,
        quantity: qty
      });

      qtyInput.value = 1;
      showNotification(`${title} ditambahkan (${qty}x)`);
      updateCartCount();
    }

    // Remove item
    if (e.target.classList.contains('simple-cart-remove')) {
      const idx = parseInt(e.target.getAttribute('data-idx'));
      items.splice(idx, 1);
      renderCartPanel();
      showNotification('Item dihapus');
    }

    // Checkout button
    if (e.target.classList.contains('simple-checkout-btn')) {
      if (items.length === 0) {
        showNotification('Keranjang kosong');
        return;
      }
      // Redirect ke cart dengan data
      sessionStorage.setItem('simple_items', JSON.stringify(items));
      window.location.href = 'cart.html';
    }
  });

  // Add qty controls to existing cards
  setTimeout(() => {
    document.querySelectorAll('.item-card:not([data-qty-added])').forEach(card => {
      card.setAttribute('data-qty-added', 'true');

      let actionsDiv = card.querySelector('.actions');
      if (!actionsDiv) {
        actionsDiv = document.createElement('div');
        actionsDiv.className = 'actions';
        card.appendChild(actionsDiv);
      }

      // Only add if not already there
      if (!actionsDiv.querySelector('.simple-qty')) {
        const html = `
          <div style="display: flex; flex-direction: column; gap: 8px; margin-bottom: 8px;">
            <div class="simple-qty">
              <button type="button" class="simple-qty-minus" style="flex: 0 0 32px; border: none; background: #f5f5f5; cursor: pointer;">−</button>
              <input type="number" data-simple-qty min="1" max="999" value="1" style="flex: 1; border: none; background: transparent; text-align: center; font-weight: 600;">
              <button type="button" class="simple-qty-plus" style="flex: 0 0 32px; border: none; background: #f5f5f5; cursor: pointer;">+</button>
            </div>
            <button type="button" class="simple-add-btn" style="padding: 10px; background: #4CAF50; color: white; border: none; border-radius: 4px; cursor: pointer; font-weight: 600;">Tambah</button>
          </div>
        `;
        actionsDiv.insertAdjacentHTML('afterbegin', html);
      }
    });
  }, 100);

  renderCartPanel();
}

function renderCartPanel() {
  let panel = document.querySelector('[data-simple-cart-panel]');
  if (!panel) {
    panel = document.createElement('div');
    panel.setAttribute('data-simple-cart-panel', '');
    document.body.appendChild(panel);
  }

  const total = items.reduce((sum, item) => sum + item.price * item.quantity, 0);

  if (items.length === 0) {
    panel.innerHTML = `
      <div style="position: fixed; bottom: 20px; right: 20px; width: 60px; height: 60px; background: #4CAF50; color: white; border-radius: 50%; display: flex; align-items: center; justify-content: center; font-size: 20px; box-shadow: 0 4px 12px rgba(0,0,0,0.15); cursor: pointer; z-index: 1001;">
        🛒 0
      </div>
    `;
    return;
  }

  panel.innerHTML = `
    <div style="position: fixed; bottom: 20px; right: 20px; width: 60px; height: 60px; background: #4CAF50; color: white; border-radius: 50%; display: flex; align-items: center; justify-content: center; font-size: 20px; box-shadow: 0 4px 12px rgba(0,0,0,0.15); cursor: pointer; z-index: 1001; user-select: none;" class="simple-cart-toggle">
      🛒 ${items.length}
    </div>

    <div style="position: fixed; right: 0; top: 0; width: 380px; height: 100vh; background: white; box-shadow: -2px 0 8px rgba(0,0,0,0.1); z-index: 1002; display: none; flex-direction: column; transform: translateX(380px); transition: transform 0.3s;" class="simple-cart-slide">
      <div style="display: flex; justify-content: space-between; padding: 16px; background: #f5f5f5; border-bottom: 1px solid #eee;">
        <h3 style="margin: 0; font-size: 16px;">Keranjang (${items.length})</h3>
        <button style="background: none; border: none; cursor: pointer; font-size: 20px; color: #666;" class="simple-cart-toggle">✕</button>
      </div>

      <div style="flex: 1; overflow-y: auto; padding: 12px;">
        ${items.map((item, idx) => `
          <div style="display: flex; gap: 10px; padding: 12px; background: white; border: 1px solid #eee; border-radius: 6px; margin-bottom: 8px;">
            <img src="${item.image}" alt="" style="width: 50px; height: 50px; object-fit: cover; border-radius: 4px;">
            <div style="flex: 1; min-width: 0;">
              <strong style="font-size: 13px; display: block; margin-bottom: 2px;">${item.title}</strong>
              <p style="margin: 0; font-size: 12px; color: #666;">${item.quantity}x Rp${item.price.toLocaleString('id-ID')}</p>
            </div>
            <div style="font-weight: 600; font-size: 12px; white-space: nowrap; padding-left: 8px;">
              Rp${(item.quantity * item.price).toLocaleString('id-ID')}
            </div>
            <button class="simple-cart-remove" data-idx="${idx}" style="background: #f0f0f0; border: none; width: 24px; height: 24px; border-radius: 50%; cursor: pointer; font-size: 12px; padding: 0;">✕</button>
          </div>
        `).join('')}
      </div>

      <div style="padding: 16px; border-top: 1px solid #eee; background: #f9f9f9;">
        <div style="display: flex; justify-content: space-between; margin-bottom: 12px; font-size: 14px; padding-bottom: 12px; border-bottom: 1px solid #eee;">
          <span>Total:</span>
          <strong style="font-size: 18px; color: #4CAF50;">Rp${total.toLocaleString('id-ID')}</strong>
        </div>
        <button class="simple-checkout-btn" style="display: block; width: 100%; padding: 12px; background: #4CAF50; color: white; border: none; border-radius: 4px; cursor: pointer; font-weight: 600; margin-bottom: 8px;">Lanjut ke Keranjang →</button>
      </div>
    </div>
  `;

  // Toggle handlers
  panel.querySelectorAll('.simple-cart-toggle').forEach(btn => {
    btn.addEventListener('click', () => {
      const slide = panel.querySelector('.simple-cart-slide');
      const isOpen = slide.style.display === 'flex';
      slide.style.display = isOpen ? 'none' : 'flex';
      slide.style.transform = isOpen ? 'translateX(380px)' : 'translateX(0)';
    });
  });
}

function updateCartCount() {
  const badge = document.querySelector('[data-simple-cart-panel]');
  if (badge) renderCartPanel();
}

function showNotification(text) {
  const notif = document.createElement('div');
  notif.textContent = text;
  notif.style.cssText = 'position: fixed; bottom: 80px; right: 20px; background: #333; color: white; padding: 12px 16px; border-radius: 4px; font-size: 13px; opacity: 0; transition: opacity 0.3s; z-index: 1003;';
  document.body.appendChild(notif);

  setTimeout(() => notif.style.opacity = '1', 10);
  setTimeout(() => {
    notif.style.opacity = '0';
    setTimeout(() => notif.remove(), 300);
  }, 2000);
}

export function getItems() {
  return items;
}
