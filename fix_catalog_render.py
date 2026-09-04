import re

with open('catalog.js', 'r') as f:
    content = f.read()

# Fix the data-price attribute - remove the ternary that's breaking it
old_article = r'<article class="card item-card order-item-card" data-item-id="\${item.id}" data-price="\${item.type === \'trip\' \|\| mode !== \'sale\' \? item.price : item.sale_price}" data-mode="\${mode}">'

new_article = '<article class="card item-card order-item-card" data-item-id="${item.id}" data-price="${item.price}" data-mode="${mode}">'

content = re.sub(
    r'<article class="card item-card order-item-card" data-item-id="\$\{item\.id\}" data-price="\$\{item\.type === \'trip\' \|\| mode !== \'sale\' \? item\.price : item\.sale_price\}" data-mode="\$\{mode\}">',
    new_article,
    content
)

# If that didn't work, do simpler fix
if 'data-price="${item.price}"' not in content:
    content = re.sub(
        r'<article class="card item-card order-item-card" data-item-id="\$\{item\.id\}"[^>]*data-mode="\$\{mode\}">',
        new_article,
        content
    )

with open('catalog.js', 'w') as f:
    f.write(content)

print("✓ Fixed data-price attribute in renderCard")
