# Catálogo — clientes empresa

Qué ve cada cliente empresa desde el presupuestador de erp-cliente. Lo configura administración en la
vista Clientes (`catalogo_clientes_habilitar`); qué parte del cálculo recibe, en `calculo.md` → *La
función de cálculo decide qué parte ve cada uno*.

- **Cada cliente empresa ve lo que administración le habilita, y el precio es opcional por cliente.**
  Nace sin nada habilitado. Se habilita por categoría o subcategoría, no por ítem: lo que se aprueba
  después en una subcategoría habilitada lo ve solo (una categoría incluye sus subcategorías futuras).
  De los insumos ve solo los sueltos. Ve lo mismo que el vendedor: nunca despiece, costo ni servicios. Sin
  precio, el cliente arma el pedido con medidas y el precio lo pone el vendedor. Descartado: marcar ítem
  por ítem (cada producto nuevo obliga a tocar cada cliente).
- **Las habilitaciones siguen a la empresa que queda al fusionar, y Clientes lista por función**
  (2026-10-22). Trigger del catálogo sobre `contactos_empresas` (`AFTER UPDATE OF fusionada_en`,
  como el de Obras sobre vínculos, `sql/146`): lo de la que se va pasa a la que queda; si las dos
  tenían, la unión de lo habilitado y el *ve precio* de la que queda (en el choque gana la que queda,
  como en Contactos). La vista Clientes lista con una función DEFINER id y nombre de toda empresa
  activa y aprobada para `catalogo_clientes`, sin datos de contacto ni la RLS de Contactos (como
  `contactos_fusionada`). Por qué: fusionada *Constructora Sur* en *Constructora del Sur SA*, el
  portal dejaba de ver Ventanas; y Laura no encontraba la empresa que cargó el equipo de Juan.
