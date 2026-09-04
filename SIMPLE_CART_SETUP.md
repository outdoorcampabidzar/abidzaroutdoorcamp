# Simple Cart - Setup Guide

## Files
- `simple-cart.js` - Core logic
- `simple-cart-styles.css` - Styling
- This guide

## Installation (3 steps)

### 1. Add stylesheet to HTML pages

In `sale.html`, `rental.html`, `item.html` - add to `<head>`:
```html
<link rel="stylesheet" href="simple-cart-styles.css">
```

### 2. Initialize on page load

Add before closing `</body>`:
```html
<script type="module">
  import { initSimpleCart } from './simple-cart.js';
  document.addEventListener('DOMContentLoaded', initSimpleCart);
</script>
```

### 3. Update card markup in catalog.js

Change `renderCard()` to include qty input and add button:

**Before:**
```html
<article class="card item-card">
  ...
</article>
```

**After:**
```html
<article class="card item-card" data-item-id="${item.id}" data-price="${item.price}" data-mode="${mode}">
  ...
  <div class="simple-qty">
    <button type="button" class="simple-qty-minus">−</button>
    <input type="number" data-simple-qty min="1" max="${available}" value="1">
    <button type="button" class="simple-qty-plus">+</button>
  </div>
  <button type="button" class="simple-add-btn">Tambah</button>
</article>
```

## How It Works

1. **Browse catalog** → Lihat qty controls di tiap card
2. **Adjust qty** → Klik +/- atau ketik jumlah
3. **Click Tambah** → Item masuk cart, notif muncul
4. **See floating cart badge** → Kanan bawah, ada counter
5. **Click badge** → Slide panel buka, lihat isi cart
6. **Click item remove** → Hapus dari cart
7. **Click "Lanjut ke Keranjang"** → Go to full cart page

## Data Format

```javascript
{
  id: "item_id",
  title: "Product Name",
  price: 100000,
  image: "url.jpg",
  quantity: 2,
  mode: "rental" // or "sale"
  added_at: "timestamp"
}
```

## Storage

- **LocalStorage**: `simple_cart` - persists across sessions
- Auto-saved on every add/remove

## Customization

Change colors in `simple-cart-styles.css`:

```css
.simple-add-btn {
  background: #4CAF50; /* Green button */
}

.simple-cart-badge {
  background: #4CAF50; /* Green floating cart */
}
```

## Done!

That's it. 3 simple steps, no complex modal, no form fields. Just qty input on card + floating cart.
