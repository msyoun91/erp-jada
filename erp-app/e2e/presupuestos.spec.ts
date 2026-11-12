import { test, expect } from "@playwright/test";
import { asegurarAprobador, como, crearIgual, panel, tarjeta } from "./comun";

const marca = `Zqx${Date.now() % 100000}`;
const nombre = `Aberturas ${marca}`;

test("admin da de alta un presupuesto y ve la lista, la ficha y la versión", async ({ browser }) => {
  test.setTimeout(120_000);
  const ctx = await browser.newContext({ storageState: "e2e/.auth/admin.json" });
  const page = await ctx.newPage();

  await page.goto("/presupuestos");
  await expect(page.getByRole("button", { name: "Nuevo presupuesto" })).toBeVisible();
  await page.screenshot({ path: "e2e/.out/pres-lista-vacia.png", fullPage: true });

  await page.getByRole("button", { name: "Nuevo presupuesto" }).click();
  const alta = panel(page);
  const obra = alta.getByLabel("Obra");
  await obra.selectOption({ index: 1 });
  await alta.getByLabel("Nombre", { exact: true }).fill(nombre);
  await alta.getByRole("button", { name: "Crear presupuesto" }).click();
  await expect(page).toHaveURL(/\/presupuestos\/[0-9a-f-]{36}$/);
  await expect(page.getByRole("heading", { name: new RegExp(nombre) })).toBeVisible();
  await page.screenshot({ path: "e2e/.out/pres-ficha.png", fullPage: true });

  await page.getByRole("link", { name: /Versión 1/ }).click();
  await expect(page).toHaveURL(/\/presupuestos\/[0-9a-f-]{36}\/[0-9a-f-]{36}$/);
  await expect(page.getByRole("heading", { name: "Versión 1" })).toBeVisible();
  await expect(page.getByRole("region", { name: "General" }).getByText("Sin renglones.")).toBeVisible();
  await page.screenshot({ path: "e2e/.out/pres-version.png", fullPage: true });

  await page.getByRole("button", { name: "Editar" }).click();
  const datos = panel(page);
  await datos.getByLabel("Nombre de la variante").fill("Aluminio");
  await datos.getByLabel("IVA").selectOption("false");
  await datos.getByLabel("Descuento").fill("5");
  await page.screenshot({ path: "e2e/.out/pres-version-datos.png", fullPage: true });
  await datos.getByRole("button", { name: "Guardar" }).click();
  await expect(page.getByRole("heading", { name: "Versión 1 · Aluminio" })).toBeVisible();
  await expect(page.getByText("IVA incluido · Descuento 5 %")).toBeVisible();

  await page.getByRole("button", { name: "Nueva sección" }).click();
  const nueva = panel(page);
  await nueva.getByLabel("Nombre").fill("Colocación");
  await nueva.getByLabel("IVA").selectOption("10.5");
  await nueva.getByRole("button", { name: "Crear sección" }).click();
  const colocacion = page.getByRole("region", { name: "Colocación" });
  await expect(colocacion.getByText("ARS · IVA 10,5 %")).toBeVisible();
  await expect(page.locator("section").first()).toHaveAttribute("aria-label", "General");

  await colocacion.getByRole("button", { name: "Más acciones" }).click();
  await page.getByRole("button", { name: "Subir" }).click();
  await expect(page.locator("section").first()).toHaveAttribute("aria-label", "Colocación");

  await page.getByRole("button", { name: "Más acciones" }).first().click();
  await page.getByRole("button", { name: "Todas las secciones…" }).click();
  const todas = panel(page);
  await todas.getByLabel("IVA").selectOption("21");
  await todas.getByRole("button", { name: "Cambiar todas" }).click();
  await expect(colocacion.getByText("ARS · IVA 21 %")).toBeVisible();
  await page.screenshot({ path: "e2e/.out/pres-version-secciones.png", fullPage: true });

  await colocacion.getByRole("button", { name: "Más acciones" }).click();
  await page.getByRole("button", { name: "Sacar" }).click();
  await page.getByRole("dialog").getByRole("button", { name: "Sacar" }).click();
  await expect(colocacion).toHaveCount(0);
  await expect(page.getByRole("region", { name: "General" }).getByRole("button", { name: "Más acciones" })).toBeVisible();

  await page.goto("/presupuestos");
  await expect(page.getByText(nombre)).toBeVisible();
  await page.screenshot({ path: "e2e/.out/pres-lista.png", fullPage: true });
  for (const filtro of ["Esperan mi autorización", "Devueltas"]) {
    await page.getByRole("button", { name: new RegExp(filtro) }).click();
    await page.screenshot({ path: `e2e/.out/pres-${filtro.slice(0, 6)}.png`, fullPage: true });
  }
  await ctx.close();
});

test("admin carga renglones a mano y de Catálogo, los edita, duplica y saca", async ({ browser }) => {
  test.setTimeout(180_000);
  const ctx = await browser.newContext({ storageState: "e2e/.auth/admin.json" });
  const page = await ctx.newPage();

  await page.goto("/presupuestos");
  await page.getByRole("button", { name: "Nuevo presupuesto" }).click();
  const alta = panel(page);
  await alta.getByLabel("Obra").selectOption({ index: 1 });
  await alta.getByLabel("Nombre", { exact: true }).fill(`Renglones ${marca}`);
  await alta.getByRole("button", { name: "Crear presupuesto" }).click();
  await expect(page).toHaveURL(/\/presupuestos\/[0-9a-f-]{36}$/);
  await page.getByRole("link", { name: /Versión 1/ }).click();
  const general = page.getByRole("region", { name: "General" });

  await general.getByRole("button", { name: "A mano" }).click();
  const mano = panel(page);
  await mano.getByLabel("Descripción").fill("Flete cerrado a Pilar");
  await mano.getByLabel(/Precio por unidad/).fill("150.000");
  await mano.getByLabel("Cantidad").fill("2");
  await mano.getByRole("button", { name: "Agregar" }).click();
  await expect(mano.getByText("Va sin puntos")).toBeVisible();
  await mano.getByLabel(/Precio por unidad/).fill("150000");
  await page.screenshot({ path: "e2e/.out/pres-renglon-mano.png", fullPage: true });
  await mano.getByRole("button", { name: "Agregar" }).click();
  await expect(mano).toBeHidden();
  const flete = general.getByRole("listitem").filter({ hasText: "Flete cerrado a Pilar" });
  await expect(flete.getByText("$ 300.000")).toBeVisible();
  await expect(flete.getByText("A mano")).toBeVisible();

  await flete.getByRole("button", { name: "Más acciones" }).click();
  await flete.getByRole("button", { name: "Editar" }).click();
  const editarMano = panel(page);
  await editarMano.getByLabel("Cantidad").fill("1");
  await editarMano.getByRole("button", { name: "Guardar" }).click();
  await expect(flete.getByText("$ 150.000")).toBeVisible();

  await general.getByRole("button", { name: "De Catálogo" }).click();
  const cat = panel(page);
  await cat.getByLabel("Designación").fill("V1");
  await cat.getByLabel("Ubicación").fill("Lavadero");
  await cat.getByLabel("Paquete").selectOption({ index: 1 });
  const ancho = cat.getByLabel(/^Ancho/);
  await expect(ancho).toBeVisible();
  await ancho.fill("1.200");
  await expect(cat.getByText("Va sin puntos y con coma")).toBeVisible();
  await expect(cat.getByRole("button", { name: "Agregar" })).toBeDisabled();
  await ancho.fill("1200");
  await cat.getByLabel(/^Alto/).fill("1000");
  await page.screenshot({ path: "e2e/.out/pres-renglon-catalogo.png", fullPage: true });
  await cat.getByRole("button", { name: "Agregar" }).click();
  await expect(cat).toBeHidden();
  const v1 = general.getByRole("listitem").filter({ hasText: "V1" });
  await expect(v1.getByText(/Lavadero/)).toBeVisible();
  await page.screenshot({ path: "e2e/.out/pres-renglones.png", fullPage: true });

  await v1.getByRole("button", { name: "Más acciones" }).click();
  await v1.getByRole("button", { name: "Duplicar" }).click();
  const dup = panel(page);
  await expect(dup.getByLabel(/^Ancho/)).toHaveValue("1200");
  await expect(dup.getByLabel("Designación")).toHaveValue("V2");
  await dup.getByRole("button", { name: "Agregar" }).click();
  await expect(dup).toBeHidden();
  const v2 = general.getByRole("listitem").filter({ hasText: "V2" });
  await expect(v2).toBeVisible();

  await v2.getByRole("button", { name: "Más acciones" }).click();
  await v2.getByRole("button", { name: "Editar" }).click();
  const ed = panel(page);
  await expect(ed.getByLabel(/^Alto/)).toHaveValue("1000");
  await ed.getByLabel("Ubicación").fill("Cocina");
  await ed.getByRole("button", { name: "Guardar" }).click();
  await expect(v2.getByText(/Cocina/)).toBeVisible();

  await v2.getByRole("button", { name: "Más acciones" }).click();
  await v2.getByRole("button", { name: "Sacar" }).click();
  await page.getByRole("dialog").getByRole("button", { name: "Sacar" }).click();
  await expect(v2).toHaveCount(0);
  await page.screenshot({ path: "e2e/.out/pres-renglones-final.png", fullPage: true });
  await ctx.close();
});

test("admin carga ventanas en serie: foco, rango, seguir cargando y lo cargado en la fila", async ({ browser }) => {
  test.setTimeout(120_000);
  const ctx = await browser.newContext({ storageState: "e2e/.auth/admin.json" });
  const page = await ctx.newPage();

  await page.goto("/presupuestos");
  await page.getByRole("button", { name: "Nuevo presupuesto" }).click();
  const alta = panel(page);
  await alta.getByLabel("Obra").selectOption({ index: 1 });
  await alta.getByLabel("Nombre", { exact: true }).fill(`Seguidas ${marca}`);
  await alta.getByRole("button", { name: "Crear presupuesto" }).click();
  await expect(page).toHaveURL(/\/presupuestos\/[0-9a-f-]{36}$/);
  await page.getByRole("link", { name: /Versión 1/ }).click();
  const general = page.getByRole("region", { name: "General" });

  await general.getByRole("button", { name: "De Catálogo" }).click();
  const cat = panel(page);
  const paquete = cat.getByLabel("Paquete");
  const cantidad = cat.locator("#renglon-cantidad");
  await expect(cat.getByLabel("Designación")).toBeFocused();
  await cat.getByLabel("Seguir cargando").check();
  await cat.getByLabel("Designación").fill("V09");
  await cat.getByLabel("Ubicación").fill("Lavadero");
  await paquete.selectOption({ index: 1 });
  const elegido = await paquete.inputValue();
  // Pasado el máximo se marca al escribir, sin esperar a guardar.
  await cat.getByLabel(/^Ancho/).fill("99999");
  await expect(cat.getByLabel(/^Ancho/)).toHaveClass(/input-error/);
  await cat.getByLabel(/^Ancho/).fill("1200");
  await expect(cat.getByLabel(/^Ancho/)).not.toHaveClass(/input-error/);
  await cantidad.fill("2");
  await cat.getByLabel(/^Alto/).fill("1000");
  await cat.getByLabel(/^Alto/).press("Enter");

  // Sigue abierto para la siguiente: avanza la designación, se limpian las medidas y queda el paquete.
  await expect(cat.getByLabel("Designación")).toHaveValue("V10");
  await expect(cat.getByLabel("Designación")).toBeFocused();
  await expect(cat.getByLabel("Ubicación")).toHaveValue("");
  await expect(cat.getByLabel(/^Ancho/)).toHaveValue("");
  await expect(cat.getByLabel(/^Alto/)).toHaveValue("");
  await expect(cantidad).toHaveValue("1");
  await expect(paquete).toHaveValue(elegido);
  await expect(cat.locator('optgroup[label="En este presupuesto"] option')).toHaveCount(1);
  const v09 = general.getByRole("listitem").filter({ hasText: "V09" });
  await expect(v09.getByText(/Lavadero · 2 u\./)).toBeVisible();
  await expect(v09.getByText(/ancho 1200 · alto 1000/i)).toBeVisible();
  await page.screenshot({ path: "e2e/.out/pres-renglon-seguir.png", fullPage: true });

  await cat.getByLabel(/^Ancho/).fill("1500");
  await cat.getByLabel(/^Alto/).fill("1100");
  await cat.getByLabel("Seguir cargando").uncheck();
  await cat.getByRole("button", { name: "Agregar" }).click();
  await expect(cat).toBeHidden();
  const v10 = general.getByRole("listitem").filter({ hasText: "V10" });
  await expect(v10.getByText(/ancho 1500 · alto 1100/i)).toBeVisible();
  await page.screenshot({ path: "e2e/.out/pres-renglones-cargado.png", fullPage: true });

  // Tocar la fila edita, sin pasar por el menú.
  await v10.getByText("V10", { exact: true }).click();
  const editar = panel(page);
  await expect(editar.getByRole("heading", { name: "Editar renglón" })).toBeVisible();
  await expect(editar.getByLabel(/^Ancho/)).toHaveValue("1500");
  await page.keyboard.press("Escape");
  await expect(editar).toBeHidden();
  await ctx.close();
});

// Necesita el paquete y el servicio de e2e/datos-opcionales.sql.
test("admin elige cómo se ven los opcionales y los tilda en cada ventana", async ({ browser }) => {
  test.setTimeout(180_000);
  const ctx = await browser.newContext({ storageState: "e2e/.auth/admin.json" });
  const page = await ctx.newPage();

  await page.goto("/presupuestos");
  await page.getByRole("button", { name: "Nuevo presupuesto" }).click();
  const alta = panel(page);
  await alta.getByLabel("Obra").selectOption({ index: 1 });
  await alta.getByLabel("Nombre", { exact: true }).fill(`Opcionales ${marca}`);
  await alta.getByRole("button", { name: "Crear presupuesto" }).click();
  await expect(page).toHaveURL(/\/presupuestos\/[0-9a-f-]{36}$/);
  await page.getByRole("link", { name: /Versión 1/ }).click();
  const general = page.getByRole("region", { name: "General" });

  await page.getByRole("button", { name: "Nueva sección" }).click();
  const nueva = panel(page);
  await nueva.getByLabel("Nombre").fill("Colocación");
  await nueva.getByLabel("IVA").selectOption("10.5");
  await nueva.getByRole("button", { name: "Crear sección" }).click();
  const colocacion = page.getByRole("region", { name: "Colocación" });
  await expect(colocacion).toBeVisible();

  await general.getByRole("button", { name: "De Catálogo" }).click();
  const cat = panel(page);
  await cat.getByLabel("Designación").fill("V1");
  await cat.getByLabel("Paquete").selectOption({ label: "Zqx197 Ventana opcionales" });
  await cat.getByLabel(/^ancho/).fill("1200");
  await cat.getByLabel(/^alto/).fill("1000");
  await cat.getByRole("button", { name: "Agregar" }).click();
  await expect(cat).toBeHidden();

  // En el precio, cada opcional es un botón.
  const v1 = general.getByRole("listitem").filter({ hasText: "V1" });
  const opcionales = v1.getByRole("group", { name: "Opcionales" });
  await expect(opcionales.getByRole("button", { name: "Mosquitero" })).toHaveAttribute("aria-pressed", "false");
  await expect(opcionales.getByRole("button", { name: "Zqx197 Colocación" })).toBeVisible();
  await page.screenshot({ path: "e2e/.out/pres-opcionales-precio.png", fullPage: true });

  await page.getByRole("button", { name: "Más acciones" }).first().click();
  await page.getByRole("button", { name: "Cómo se ven los opcionales…" }).click();
  const como = panel(page);
  await como.getByLabel("Mosquitero").selectOption("debajo");
  await como.getByLabel("Zqx197 Colocación").selectOption({ label: "Colocación · ARS · IVA 10,5 %" });
  await page.screenshot({ path: "e2e/.out/pres-opcionales-panel.png", fullPage: true });
  await como.getByRole("button", { name: "Guardar" }).click();
  await expect(como).toBeHidden();

  // Debajo, la línea es la casilla: sin elegir, sin monto.
  const mosquitero = opcionales.getByRole("checkbox", { name: "Mosquitero" });
  await expect(mosquitero).not.toBeChecked();
  await mosquitero.check();
  await expect(opcionales.getByText("$ 9.600")).toBeVisible();

  // La Cortina lleva el Cajón.
  await opcionales.getByRole("button", { name: "Cortina" }).click();
  await expect(page.getByText("Cortina lleva Cajón.")).toBeVisible();
  await expect(opcionales.getByRole("button", { name: "Cajón" })).toHaveAttribute("aria-pressed", "true");
  await expect(opcionales.getByRole("button", { name: "Cortina" })).toHaveAttribute("aria-pressed", "true");

  // Aparte: un renglón en su sección, que no se saca mientras lo tenga.
  await opcionales.getByRole("button", { name: "Zqx197 Colocación" }).click();
  const aparte = colocacion.getByRole("listitem").filter({ hasText: "Zqx197 Colocación" });
  await expect(aparte.getByText("De 1 ventana")).toBeVisible();
  await page.screenshot({ path: "e2e/.out/pres-opcionales-elegidos.png", fullPage: true });
  await colocacion.getByRole("button", { name: "Más acciones" }).click();
  await expect(page.getByRole("button", { name: "Sacar" })).toHaveCount(0);
  await page.keyboard.press("Escape");

  await page.getByRole("button", { name: "Más acciones" }).first().click();
  await page.getByRole("button", { name: "Cómo se ven los opcionales…" }).click();
  const vuelta = panel(page);
  await vuelta.getByLabel("Zqx197 Colocación").selectOption("precio");
  await vuelta.getByRole("button", { name: "Guardar" }).click();
  await expect(aparte).toHaveCount(0);
  await expect(opcionales.getByRole("button", { name: "Zqx197 Colocación" })).toHaveAttribute("aria-pressed", "true");

  await mosquitero.uncheck();
  await expect(opcionales.getByText("$ 9.600")).toHaveCount(0);
  await ctx.close();
});

// Necesita e2e/datos-autorizaciones.sql: tope 10 %, Tester arma sin autorizar y Admin autoriza. La obra no puede estar
// congelada: publicar la mueve a cotización (OB018).
test("tester pide, retira y publica; admin devuelve y autoriza", async ({ browser }) => {
  test.setTimeout(240_000);
  const vendedor = await como(browser, "tester");
  const jefe = await como(browser, "admin");
  const page = vendedor.page;
  const nombreAut = `Autorizar ${marca}`;
  const confirmar = (p: typeof page, boton: string) => p.getByRole("dialog").getByRole("button", { name: boton }).click();

  await page.goto("/presupuestos");
  await page.getByRole("button", { name: "Nuevo presupuesto" }).click();
  const alta = panel(page);
  await alta.getByLabel("Obra").selectOption({ label: "Edificio Norte Zqx20218 A" });
  await alta.getByLabel("Nombre", { exact: true }).fill(nombreAut);
  await alta.getByRole("button", { name: "Crear presupuesto" }).click();
  await expect(page).toHaveURL(/\/presupuestos\/[0-9a-f-]{36}$/);
  await page.getByRole("link", { name: /Versión 1/ }).click();
  await expect(page).toHaveURL(/\/presupuestos\/[0-9a-f-]{36}\/[0-9a-f-]{36}$/);
  const url = page.url();

  const antes = page.getByRole("region", { name: "Antes de publicar" });
  await expect(antes.getByText("La versión no tiene renglones")).toBeVisible();
  await expect(antes.getByRole("button", { name: "Publicar" })).toBeDisabled();

  // A mano no pide nada; el descuento sobre el tope, al jefe.
  await page.getByRole("region", { name: "General" }).getByRole("button", { name: "A mano" }).click();
  const mano = panel(page);
  await mano.getByLabel("Descripción").fill("Flete cerrado a Pilar");
  await mano.getByLabel(/Precio por unidad/).fill("150000");
  await mano.getByRole("button", { name: "Agregar" }).click();
  await expect(mano).toBeHidden();
  await expect(antes.getByText("Nada pide autorización: se puede publicar.")).toBeVisible();
  await page.getByRole("button", { name: "Editar" }).click();
  const datos = panel(page);
  await datos.getByLabel("Descuento").fill("15");
  await datos.getByRole("button", { name: "Guardar" }).click();
  await expect(datos).toBeHidden();
  const delJefe = antes.getByRole("listitem").filter({ hasText: "Del jefe comercial" });
  await expect(delJefe.getByText("Falta pedirla")).toBeVisible();
  await expect(delJefe.getByText("Descuento de 15 %, sobre el tope de 10 %")).toBeVisible();
  await page.screenshot({ path: "e2e/.out/pres-antes-borrador.png", fullPage: true });

  await antes.getByRole("button", { name: "Pedir autorización" }).click();
  await confirmar(page, "Pedir");
  await expect(delJefe.getByText("Pendiente")).toBeVisible();
  await expect(page.getByText("En revisión", { exact: true })).toBeVisible();
  await expect(page.getByRole("button", { name: "Editar" })).toHaveCount(0);
  await expect(antes.getByRole("button", { name: "Publicar" })).toBeDisabled();
  await page.screenshot({ path: "e2e/.out/pres-antes-revision.png", fullPage: true });

  await antes.getByRole("button", { name: "Retirar de revisión" }).click();
  await confirmar(page, "Retirar");
  await expect(delJefe.getByText("Falta pedirla")).toBeVisible();
  await antes.getByRole("button", { name: "Pedir autorización" }).click();
  await confirmar(page, "Pedir");
  await expect(delJefe.getByText("Pendiente")).toBeVisible();

  // El jefe la encuentra en su filtro y la devuelve.
  const j = jefe.page;
  await j.goto("/presupuestos");
  await j.getByRole("button", { name: /Esperan mi autorización/ }).click();
  await j.getByRole("link", { name: new RegExp(nombreAut) }).click();
  await expect(j).toHaveURL(url);
  const antesJefe = j.getByRole("region", { name: "Antes de publicar" });
  await expect(antesJefe.getByText("Pedida por Tester")).toBeVisible();
  await j.screenshot({ path: "e2e/.out/pres-antes-jefe.png", fullPage: true });
  await antesJefe.getByRole("button", { name: "Devolver" }).click();
  const devolver = panel(j);
  await devolver.getByRole("button", { name: "Devolver" }).click();
  await expect(devolver.getByText("Escribí el motivo")).toBeVisible();
  await devolver.getByLabel("Motivo").fill("El descuento va hasta 12 %");
  await devolver.getByRole("button", { name: "Devolver" }).click();
  await expect(devolver).toBeHidden();
  await expect(antesJefe.getByText("Devuelta por vos")).toBeVisible();

  // Quien armó ve el motivo, corrige y pide de nuevo.
  // El nombre de quien resolvió sale de `obras_nombres`: Admin está solo si actuó en la obra.
  await page.reload();
  await expect(antes.getByText(/^Devuelta( por Admin)? el/)).toBeVisible();
  await expect(antes.getByText("El descuento va hasta 12 %")).toBeVisible();
  await page.screenshot({ path: "e2e/.out/pres-antes-devuelta.png", fullPage: true });
  await page.getByRole("button", { name: "Editar" }).click();
  const corregir = panel(page);
  await corregir.getByLabel("Descuento").fill("12");
  await corregir.getByRole("button", { name: "Guardar" }).click();
  await expect(corregir).toBeHidden();
  await antes.getByRole("button", { name: "Pedir autorización" }).click();
  await confirmar(page, "Pedir");
  await expect(delJefe.getByText("Pendiente")).toBeVisible();

  await j.reload();
  await antesJefe.getByRole("button", { name: "Autorizar" }).click();
  await confirmar(j, "Autorizar");
  await expect(antesJefe.getByText("Autorizada por vos")).toBeVisible();
  await expect(antesJefe.getByText("Autorizaron todo: lista para publicar.")).toBeVisible();

  // Publica quien armó.
  await page.reload();
  await expect(delJefe.getByText(/^Autorizada( por Admin)? el/)).toBeVisible();
  await antes.getByRole("button", { name: "Publicar" }).click();
  await expect(page.getByRole("dialog").getByText("vence en 15 días")).toBeVisible();
  await confirmar(page, "Publicar");
  await expect(page.getByText("Publicada", { exact: true })).toBeVisible();
  await expect(antes).toHaveCount(0);
  await expect(page.getByText(/Vence el/)).toBeVisible();
  await page.screenshot({ path: "e2e/.out/pres-antes-publicada.png", fullPage: true });

  await vendedor.ctx.close();
  await jefe.ctx.close();
});

// Necesita e2e/datos-mantener.sql (y antes datos-opcionales.sql): la variante 2, copiada de la 1, en borrador. Arranca y
// termina con todo a hoy, así se puede correr de nuevo.
test("admin mantiene o pasa a hoy cada ventana copiada, y todas juntas", async ({ browser }) => {
  test.setTimeout(180_000);
  const { ctx, page } = await como(browser, "admin");
  const confirmar = (boton: string) => page.getByRole("dialog").getByRole("button", { name: boton }).click();

  await page.goto("/presupuestos");
  // La lista se pagina, y cada corrida suma presupuestos: se busca.
  await page.getByPlaceholder("Buscar por número, nombre u obra…").fill("Mantener Zqx198");
  await page.getByRole("link", { name: /Mantener Zqx198/ }).click();
  await page.getByRole("link", { name: /Versión 2/ }).click();
  const version = tarjeta(page, "Versión 2");
  await expect(version).toBeVisible();
  const v1 = page.getByRole("region", { name: "General" }).getByRole("listitem").filter({ hasText: "V1" }).first();
  const antes = page.getByRole("region", { name: "Antes de publicar" });
  const delJefe = antes.getByRole("listitem").filter({ hasText: "Del jefe comercial" });
  const todasAHoy = async () => {
    await version.getByRole("button", { name: "Más acciones" }).click();
    await page.getByRole("button", { name: "Todas a hoy…" }).click();
    await expect(page.getByRole("dialog").getByText("Las ventanas y los mínimos se recalculan")).toBeVisible();
    await confirmar("Pasar a hoy");
    // Arranca ya a hoy: lo de abajo se cumple antes de que vuelva la acción, y la página redibujada cerraba el menú siguiente.
    await expect(page.getByRole("dialog")).toBeHidden();
    await expect(page.getByText(/^Precios del/)).toHaveCount(0);
    await expect(delJefe).toHaveCount(0);
  };

  await todasAHoy();

  // Una por una: mantener pide autorización del jefe, aunque el precio no cambie.
  await v1.getByRole("button", { name: "Más acciones" }).click();
  await page.getByRole("button", { name: /^Mantener precios del/ }).click();
  await expect(v1.getByText(/^Precios del/)).toBeVisible();
  await expect(delJefe.getByText("1 renglón mantenido")).toBeVisible();
  await expect(delJefe.getByText("Falta pedirla")).toBeVisible();
  await page.screenshot({ path: "e2e/.out/pres-mantener-una.png", fullPage: true });
  await v1.getByRole("button", { name: "Más acciones" }).click();
  await expect(page.getByRole("button", { name: "Actualizar a hoy" })).toHaveCount(0);
  await page.getByRole("button", { name: "Pasar a hoy" }).click();
  await expect(v1.getByText(/^Precios del/)).toHaveCount(0);
  await expect(delJefe).toHaveCount(0);

  // Todas juntas, y de vuelta a hoy.
  await version.getByRole("button", { name: "Más acciones" }).click();
  await page.getByRole("button", { name: "Mantener todas…" }).click();
  await expect(page.getByRole("dialog").getByText(/Los 2 renglones copiados vuelven/)).toBeVisible();
  await confirmar("Mantener");
  await expect(page.getByText(/^Precios del/)).toHaveCount(2);
  await expect(delJefe.getByText("2 renglones mantenidos")).toBeVisible();
  await page.screenshot({ path: "e2e/.out/pres-mantener-todas.png", fullPage: true });
  await version.getByRole("button", { name: "Más acciones" }).click();
  await expect(page.getByRole("button", { name: "Mantener todas…" })).toHaveCount(0);
  await page.keyboard.press("Escape");
  await todasAHoy();

  await ctx.close();
});

// Necesita e2e/datos-autorizaciones.sql (tope y plazo). Publicar mueve la obra a cotización: no puede estar congelada (OB018).
test("admin renombra, corrige, descarta, suma una variante y la quita", async ({ browser }) => {
  test.setTimeout(240_000);
  const { ctx, page } = await como(browser, "admin");
  const confirmar = (boton: string) => page.getByRole("dialog").getByRole("button", { name: boton }).click();
  const menu = async (card: ReturnType<typeof tarjeta>, accion: string | RegExp) => {
    await card.getByRole("button", { name: "Más acciones" }).click();
    await page.getByRole("button", { name: accion }).click();
  };
  const publicar = async () => {
    const antes = page.getByRole("region", { name: "Antes de publicar" });
    await antes.getByRole("button", { name: "Publicar" }).click();
    await confirmar("Publicar");
    await expect(page.getByText("Publicada", { exact: true })).toBeVisible();
  };

  await page.goto("/presupuestos");
  await page.getByRole("button", { name: "Nuevo presupuesto" }).click();
  const alta = panel(page);
  await alta.getByLabel("Obra").selectOption({ label: "Edificio Norte Zqx20218 A" });
  await alta.getByLabel("Nombre", { exact: true }).fill(`Ficha ${marca}`);
  await alta.getByRole("button", { name: "Crear presupuesto" }).click();
  await expect(page).toHaveURL(/\/presupuestos\/[0-9a-f-]{36}$/);
  const ficha = page.url();

  await page.getByRole("button", { name: "Editar" }).click();
  const datos = panel(page);
  await datos.getByLabel("Nombre").fill(`Ficha ${marca} Belgrano`);
  await datos.getByRole("button", { name: "Guardar" }).click();
  await expect(page.getByRole("heading", { name: new RegExp(`Ficha ${marca} Belgrano`) })).toBeVisible();

  // Un borrador solo no se corrige ni se descarta.
  const unica = tarjeta(page, "Presupuesto");
  await expect(unica.getByRole("button", { name: "Corregir" })).toHaveCount(0);
  await unica.getByRole("button", { name: "Más acciones" }).click();
  await expect(page.getByRole("button", { name: /^Descartar/ })).toHaveCount(0);
  await page.keyboard.press("Escape");

  await page.getByRole("link", { name: /Versión 1/ }).click();
  await page.getByRole("region", { name: "General" }).getByRole("button", { name: "A mano" }).click();
  const mano = panel(page);
  await mano.getByLabel("Descripción").fill("Flete cerrado a Pilar");
  await mano.getByLabel(/Precio por unidad/).fill("150000");
  await mano.getByRole("button", { name: "Agregar" }).click();
  await expect(mano).toBeHidden();
  await publicar();

  // Corregir abre la versión 2 en borrador; descartarla deja de nuevo la publicada sola.
  await page.goto(ficha);
  await unica.getByRole("button", { name: "Corregir" }).click();
  await expect(page.getByRole("heading", { name: "Versión 2" })).toBeVisible();
  await expect(page.getByText("Borrador", { exact: true })).toBeVisible();
  await page.goto(ficha);
  await expect(unica.getByRole("button", { name: "Corregir" })).toHaveCount(0);
  await page.screenshot({ path: "e2e/.out/pres-ficha-corrigiendo.png", fullPage: true });
  await menu(unica, "Descartar la versión 2…");
  await expect(page.getByRole("dialog").getByText("El cliente sigue viendo la publicada")).toBeVisible();
  await confirmar("Descartar");
  await expect(page.getByRole("link", { name: /Versión 2/ })).toHaveCount(0);
  await expect(unica.getByRole("button", { name: "Corregir" })).toBeVisible();

  // Sumar variante copia la publicada; se publica con nombre, y con dos publicadas una se quita.
  await menu(unica, "Sumar variante a partir de esta");
  await expect(page.getByRole("heading", { name: "Versión 3" })).toBeVisible();
  await expect(page.getByRole("region", { name: "General" }).getByText("Flete cerrado a Pilar")).toBeVisible();
  await page.getByRole("button", { name: "Editar" }).click();
  const variante = panel(page);
  await variante.getByLabel("Nombre de la variante").fill("PVC");
  await variante.getByRole("button", { name: "Guardar" }).click();
  await expect(variante).toBeHidden();
  await publicar();

  await page.goto(ficha);
  const pvc = tarjeta(page, "PVC");
  await expect(tarjeta(page, "Variante 1")).toBeVisible();
  await page.screenshot({ path: "e2e/.out/pres-ficha-variantes.png", fullPage: true });
  await menu(pvc, "Quitar variante…");
  await expect(page.getByRole("dialog").getByText(/^PVC deja de ofrecerse/)).toBeVisible();
  await confirmar("Quitar");
  await expect(pvc.getByText("Quitada", { exact: true })).toBeVisible();
  await expect(pvc.getByRole("button", { name: "Corregir" })).toHaveCount(0);
  await tarjeta(page, "Variante 1").getByRole("button", { name: "Más acciones" }).click();
  await expect(page.getByRole("button", { name: "Quitar variante…" })).toHaveCount(0);
  await page.keyboard.press("Escape");
  await page.screenshot({ path: "e2e/.out/pres-ficha-quitada.png", fullPage: true });

  await ctx.close();
});

// Necesita e2e/datos-autorizaciones.sql (tope y plazo). Aprobar y revertir mueven la obra: no puede estar congelada (OB018).
// Termina publicado, así la obra queda como estaba.
test("admin aprueba, rechaza y revierte; tester no revierte; un borrador se desactiva", async ({ browser }) => {
  test.setTimeout(300_000);
  const { ctx, page } = await como(browser, "admin");
  const vendedor = await como(browser, "tester");
  const dialogo = page.getByRole("dialog");
  const cabecera = page.locator("div.card").first();
  const nuevo = async (nombrePres: string) => {
    await page.goto("/presupuestos");
    await page.getByRole("button", { name: "Nuevo presupuesto" }).click();
    const alta = panel(page);
    await alta.getByLabel("Obra").selectOption({ label: "Edificio Norte Zqx20218 A" });
    await alta.getByLabel("Nombre", { exact: true }).fill(nombrePres);
    await alta.getByRole("button", { name: "Crear presupuesto" }).click();
    await expect(page).toHaveURL(/\/presupuestos\/[0-9a-f-]{36}$/);
    return page.url();
  };
  const publicar = async () => {
    const antes = page.getByRole("region", { name: "Antes de publicar" });
    await antes.getByRole("button", { name: "Publicar" }).click();
    await dialogo.getByRole("button", { name: "Publicar" }).click();
    await expect(page.getByText("Publicada", { exact: true })).toBeVisible();
  };
  const revertir = async (titulo: string, causa: string) => {
    await cabecera.getByRole("button", { name: "Más acciones" }).click();
    await page.getByRole("button", { name: "Revertir…" }).click();
    await expect(dialogo.getByRole("heading", { name: titulo })).toBeVisible();
    await dialogo.getByLabel("Por qué se revierte").fill(causa);
    await dialogo.getByRole("button", { name: "Revertir" }).click();
    await expect(dialogo).toBeHidden();
    await expect(cabecera.getByText("Publicado", { exact: true })).toBeVisible();
  };

  // Dos variantes publicadas y una corrección abierta.
  const ficha = await nuevo(`Aprobar ${marca}`);
  await expect(page.getByRole("button", { name: "Aprobar" })).toHaveCount(0);
  await page.getByRole("link", { name: /Versión 1/ }).click();
  await page.getByRole("region", { name: "General" }).getByRole("button", { name: "A mano" }).click();
  const mano = panel(page);
  await mano.getByLabel("Descripción").fill("Flete cerrado a Pilar");
  await mano.getByLabel(/Precio por unidad/).fill("150000");
  await mano.getByRole("button", { name: "Agregar" }).click();
  await expect(mano).toBeHidden();
  await publicar();
  await page.goto(ficha);
  await tarjeta(page, "Presupuesto").getByRole("button", { name: "Más acciones" }).click();
  await page.getByRole("button", { name: "Sumar variante a partir de esta" }).click();
  await expect(page.getByRole("heading", { name: "Versión 2" })).toBeVisible();
  await page.getByRole("button", { name: "Editar" }).click();
  const variante = panel(page);
  await variante.getByLabel("Nombre de la variante").fill("PVC");
  await variante.getByRole("button", { name: "Guardar" }).click();
  await expect(variante).toBeHidden();
  await publicar();
  await page.goto(ficha);
  await tarjeta(page, "Variante 1").getByRole("button", { name: "Corregir" }).click();
  await expect(page.getByRole("heading", { name: "Versión 3" })).toBeVisible();

  // Aprobar pide la variante, inhabilita la otra y descarta la abierta.
  await page.goto(ficha);
  await cabecera.getByRole("button", { name: "Aprobar" }).click();
  await expect(dialogo.getByText("La versión 3, sin publicar, se descarta.", { exact: false })).toBeVisible();
  await dialogo.getByRole("button", { name: "Aprobar" }).click();
  await expect(dialogo.getByText("Elegí la variante que aprobó el cliente")).toBeVisible();
  await dialogo.getByRole("radio", { name: /^PVC/ }).check();
  await page.screenshot({ path: "e2e/.out/pres-aprobar.png", fullPage: true });
  await dialogo.getByRole("button", { name: "Aprobar" }).click();
  await expect(dialogo).toBeHidden();
  await expect(cabecera.getByText("Aprobado", { exact: true })).toBeVisible();
  await expect(tarjeta(page, "PVC").getByText("Aprobada", { exact: true })).toBeVisible();
  await expect(tarjeta(page, "Variante 1").getByText("Inhabilitada", { exact: true })).toBeVisible();
  await expect(page.getByRole("link", { name: /Versión 3/ })).toHaveCount(0);
  await expect(page.getByRole("button", { name: "Editar" })).toHaveCount(0);
  await expect(page.getByRole("button", { name: "Corregir" })).toHaveCount(0);
  await page.screenshot({ path: "e2e/.out/pres-aprobado.png", fullPage: true });

  // Revierte quien autoriza: Tester arma, pero no autoriza.
  await vendedor.page.goto(ficha);
  await expect(vendedor.page.getByText("Aprobado", { exact: true })).toBeVisible();
  await expect(vendedor.page.locator("div.card").getByRole("button", { name: "Más acciones" })).toHaveCount(0);

  await cabecera.getByRole("button", { name: "Más acciones" }).click();
  await page.getByRole("button", { name: "Revertir…" }).click();
  await dialogo.getByRole("button", { name: "Revertir" }).click();
  await expect(dialogo.getByText("Escribí por qué se revierte")).toBeVisible();
  await dialogo.getByRole("button", { name: "Volver" }).click();
  await revertir("Revertir la aprobación", "Se aprobó PVC y el cliente eligió Aluminio");
  await expect(cabecera.getByText("Se aprobó PVC y el cliente eligió Aluminio")).toBeVisible();
  await expect(tarjeta(page, "PVC").getByText("Publicada", { exact: true })).toBeVisible();

  // Rechazar pide motivo, y con "Otro", el detalle.
  await cabecera.getByRole("button", { name: "Rechazar" }).click();
  await dialogo.getByLabel("Motivo").selectOption({ label: "Otro" });
  await dialogo.getByRole("button", { name: "Rechazar" }).click();
  await expect(dialogo.getByText("Contá qué pasó")).toBeVisible();
  await dialogo.getByLabel("Motivo").selectOption({ label: "Precio" });
  await dialogo.getByLabel("Detalle").fill("Estuvimos 10% más caros");
  await dialogo.getByRole("button", { name: "Rechazar" }).click();
  await expect(dialogo).toBeHidden();
  await expect(cabecera.getByText("Rechazado", { exact: true })).toBeVisible();
  await expect(cabecera.getByText("Precio.")).toBeVisible();
  await expect(cabecera.getByText("Estuvimos 10% más caros")).toBeVisible();
  await page.screenshot({ path: "e2e/.out/pres-rechazado.png", fullPage: true });
  await revertir("Revertir el rechazo", "Se registró en el presupuesto equivocado");

  // Un borrador se desactiva y sale de la lista.
  await nuevo(`Desactivar ${marca}`);
  await cabecera.getByRole("button", { name: "Más acciones" }).click();
  await page.getByRole("button", { name: "Desactivar…" }).click();
  await dialogo.getByRole("button", { name: "Desactivar" }).click();
  await expect(page).toHaveURL(/\/presupuestos$/);
  await expect(page.getByText(`Desactivar ${marca}`)).toHaveCount(0);

  await vendedor.ctx.close();
  await ctx.close();
});

// Necesita e2e/datos-revision.sql (y antes datos-opcionales.sql y datos-autorizaciones.sql): el paquete Zqx198, que avisa
// sobre 2000 de alto, y Tester 2 como Técnica. La obra no puede estar congelada: publicar la mueve a cotización (OB018).
test("tester pide por una alerta; Técnica la ve sin precios, mira el despiece, devuelve y autoriza", async ({ browser }) => {
  test.setTimeout(240_000);
  const vendedor = await como(browser, "tester");
  const tecnica = await como(browser, "tester2");
  const page = vendedor.page;
  const t = tecnica.page;
  const nombreRev = `Revisión ${marca}`;
  const confirmar = (p: typeof page, boton: string) => p.getByRole("dialog").getByRole("button", { name: boton }).click();

  await page.goto("/presupuestos");
  await page.getByRole("button", { name: "Nuevo presupuesto" }).click();
  const alta = panel(page);
  await alta.getByLabel("Obra").selectOption({ label: "Edificio Norte Zqx20218 A" });
  await alta.getByLabel("Nombre", { exact: true }).fill(nombreRev);
  await alta.getByRole("button", { name: "Crear presupuesto" }).click();
  await expect(page).toHaveURL(/\/presupuestos\/[0-9a-f-]{36}$/);
  await page.getByRole("link", { name: /Versión 1/ }).click();
  await expect(page).toHaveURL(/\/presupuestos\/[0-9a-f-]{36}\/[0-9a-f-]{36}$/);
  const codigo = (await page.getByRole("link", { name: new RegExp(nombreRev) }).textContent())?.split(" · ")[0] ?? "";

  const general = page.getByRole("region", { name: "General" });
  for (const [designacion, alto] of [["V1", "2400"], ["V2", "1500"]]) {
    await general.getByRole("button", { name: "De Catálogo" }).click();
    const cat = panel(page);
    await cat.getByLabel("Designación").fill(designacion);
    await cat.getByLabel("Paquete").selectOption({ label: "Zqx198 Ventana alta" });
    await cat.getByLabel(/^ancho/).fill("1200");
    await cat.getByLabel(/^alto/).fill(alto);
    await cat.getByRole("button", { name: "Agregar" }).click();
    await expect(cat).toBeHidden();
  }
  const antes = page.getByRole("region", { name: "Antes de publicar" });
  const deTecnica = antes.getByRole("listitem").filter({ hasText: "De Técnica · V1" });
  await expect(deTecnica.getByText("Falta pedirla")).toBeVisible();
  await antes.getByRole("button", { name: "Pedir autorización" }).click();
  await confirmar(page, "Pedir");
  await expect(deTecnica.getByText("Pendiente")).toBeVisible();

  // Técnica no tiene la lista: el menú la lleva a su pestaña, una fila por versión.
  await t.goto("/presupuestos");
  await expect(t).toHaveURL(/\/presupuestos\/revision$/);
  const fila = t.getByRole("link", { name: new RegExp(`^${codigo} · v1`) });
  await expect(fila.getByText("Muy alta para una hoja")).toBeVisible();
  await expect(fila.getByText(/^Tester ·/)).toBeVisible();
  await t.screenshot({ path: "e2e/.out/pres-revision-lista.png", fullPage: true });

  await fila.click();
  await expect(t.getByRole("heading", { name: `${codigo} · v1` })).toBeVisible();
  const esperan = t.getByRole("region", { name: "Esperan tu revisión" });
  const v1 = esperan.getByRole("listitem").filter({ hasText: "V1" });
  await expect(v1.getByText("ancho 1200 · alto 2400")).toBeVisible();
  await expect(v1.getByText("Muy alta para una hoja")).toBeVisible();
  const resto = t.getByRole("region", { name: "El resto de la versión" });
  await expect(resto.getByText("ancho 1200 · alto 1500")).toBeVisible();
  // La barra lateral muestra los tipos de cambio: los precios, en la página.
  await expect(t.getByRole("main").getByText("$")).toHaveCount(0);
  await expect(t.getByRole("main").getByText(nombreRev)).toHaveCount(0);
  await t.screenshot({ path: "e2e/.out/pres-revision-version.png", fullPage: true });

  // El despiece, en Catálogo, con lo cargado en la ventana.
  await v1.getByRole("link", { name: "Ver despiece" }).click();
  await expect(t).toHaveURL(/\/catalogo\/paquetes\/versiones\/[0-9a-f-]{36}\?entrada=/);
  await expect(t.getByLabel("Caso de prueba")).toHaveValue("ventana");
  await expect(t.getByLabel(/^alto/)).toHaveValue("2400");
  await expect(t.getByText("Muy alta para una hoja")).toBeVisible();
  await t.screenshot({ path: "e2e/.out/pres-revision-despiece.png", fullPage: true });
  await t.goBack();

  // Devolver una ventana devuelve la versión entera.
  await v1.getByRole("button", { name: "Devolver" }).click();
  const devolver = panel(t);
  await devolver.getByLabel("Motivo").fill("Con 2400 de alto lleva refuerzo");
  await devolver.getByRole("button", { name: "Devolver" }).click();
  await expect(devolver).toBeHidden();
  await expect(t.getByText("Nada espera tu revisión en esta versión.")).toBeVisible();
  await expect(t.getByRole("region", { name: "La versión" }).getByText("Devuelta")).toBeVisible();

  await page.reload();
  await expect(antes.getByText("Con 2400 de alto lleva refuerzo")).toBeVisible();
  await antes.getByRole("button", { name: "Pedir autorización" }).click();
  await confirmar(page, "Pedir");
  await expect(deTecnica.getByText("Pendiente")).toBeVisible();

  await t.goto("/presupuestos/revision");
  await fila.click();
  await v1.getByRole("button", { name: "Autorizar" }).click();
  await confirmar(t, "Autorizar");
  await expect(t.getByText("Nada espera tu revisión en esta versión.")).toBeVisible();
  await expect(t.getByRole("region", { name: "La versión" }).getByRole("listitem").filter({ hasText: "V1" }).getByText("Autorizada")).toBeVisible();
  await t.screenshot({ path: "e2e/.out/pres-revision-autorizada.png", fullPage: true });
  await t.goto("/presupuestos/revision");
  await expect(fila).toHaveCount(0);

  // Publica quien armó.
  await page.reload();
  await expect(deTecnica.getByText("Autorizada", { exact: true })).toBeVisible();
  await antes.getByRole("button", { name: "Publicar" }).click();
  await confirmar(page, "Publicar");
  await expect(page.getByText("Publicada", { exact: true })).toBeVisible();

  await vendedor.ctx.close();
  await tecnica.ctx.close();
});

test("admin cambia el tope y el plazo, el historial lo guarda; tester no ve Configuración", async ({ browser }) => {
  const admin = await como(browser, "admin");
  const tester = await como(browser, "tester");
  const page = admin.page;

  await page.goto("/presupuestos");
  await page.locator('[data-tour="presupuestos_tabs"]').getByRole("link", { name: "Configuración" }).click();
  await expect(page).toHaveURL(/\/presupuestos\/configuracion$/);
  const vigente = page.getByRole("region", { name: "Vigente" });
  await expect(vigente.getByText(/^Desde el /)).toBeVisible();

  // Lo que había vuelve al final: los demás tests cuentan con el tope de prueba.
  await vigente.getByRole("button", { name: "Cambiar" }).click();
  const cambiar = panel(page);
  const tope = cambiar.getByLabel(/^Descuento sin autorización/);
  const plazo = cambiar.getByLabel(/^Plazo de vencimiento/);
  const antes = { tope: await tope.inputValue(), plazo: await plazo.inputValue() };
  await tope.fill("");
  await plazo.fill("400");
  await cambiar.getByRole("button", { name: "Guardar" }).click();
  await expect(cambiar.getByText("Escribí el tope")).toBeVisible();
  await expect(cambiar.getByText("Hasta 365 días")).toBeVisible();
  await tope.fill("12.5");
  await plazo.fill("20");
  await cambiar.getByRole("button", { name: "Guardar" }).click();
  await expect(cambiar).toBeHidden();
  await expect(vigente.getByText("hasta 12,5 %")).toBeVisible();
  await expect(vigente.getByText("20 días")).toBeVisible();
  await expect(vigente.getByText(/· Admin$/)).toBeVisible();
  const historial = page.getByRole("region", { name: "Historial" });
  await expect(historial.getByRole("listitem").first()).toContainText("12,5 % · 20 días");
  await expect(historial.getByRole("listitem").nth(1)).toContainText(`${antes.tope.replace(".", ",")} % · ${antes.plazo} días`);
  await page.screenshot({ path: "e2e/.out/pres-configuracion.png", fullPage: true });

  await vigente.getByRole("button", { name: "Cambiar" }).click();
  await panel(page).getByLabel(/^Descuento sin autorización/).fill(antes.tope);
  await panel(page).getByLabel(/^Plazo de vencimiento/).fill(antes.plazo);
  await panel(page).getByRole("button", { name: "Guardar" }).click();
  await expect(panel(page)).toBeHidden();
  await expect(historial.getByRole("listitem").first()).toContainText(`${antes.tope.replace(".", ",")} % · ${antes.plazo} días`);

  // Tester arma, pero no configura: sin la pestaña y sin la página.
  await tester.page.goto("/presupuestos");
  await expect(tester.page.locator('[data-tour="presupuestos_tabs"]')).toHaveCount(0);
  await tester.page.goto("/presupuestos/configuracion");
  await expect(tester.page.getByText("No encontramos esta página")).toBeVisible();

  await admin.ctx.close();
  await tester.ctx.close();
});

// Necesita e2e/datos-opcionales.sql (Zqx197) y datos-autorizaciones.sql (plazo). Aprobar mueve la obra: termina revertido,
// publicado, así la obra queda como estaba.
test("admin imprime lo publicado: cada variante con lo cargado, debajo y aparte; aprobado, solo la aprobada", async ({ browser }) => {
  test.setTimeout(240_000);
  const { ctx, page } = await como(browser, "admin");
  const dialogo = page.getByRole("dialog");
  const cabecera = page.locator("div.card").first();
  const publicar = async () => {
    await page.getByRole("region", { name: "Antes de publicar" }).getByRole("button", { name: "Publicar" }).click();
    await dialogo.getByRole("button", { name: "Publicar" }).click();
    await expect(page.getByText("Publicada", { exact: true })).toBeVisible();
  };

  await page.goto("/presupuestos");
  await page.getByRole("button", { name: "Nuevo presupuesto" }).click();
  const alta = panel(page);
  await alta.getByLabel("Obra").selectOption({ label: "Edificio Norte Zqx20218 A" });
  await alta.getByLabel("Nombre", { exact: true }).fill(`Impreso ${marca}`);
  await alta.getByRole("button", { name: "Crear presupuesto" }).click();
  await expect(page).toHaveURL(/\/presupuestos\/[0-9a-f-]{36}$/);
  const ficha = page.url();

  // Un borrador no se imprime.
  await expect(cabecera.getByRole("link", { name: "Imprimir" })).toHaveCount(0);
  await page.goto(`${ficha}/imprimir`);
  await expect(page.getByText("Un borrador no se imprime: primero se publica.")).toBeVisible();
  await page.goto(ficha);

  // Aluminio: una ventana con el Mosquitero debajo, la Cortina en el precio y la Colocación aparte, y un flete a mano.
  await page.getByRole("link", { name: /Versión 1/ }).click();
  await expect(page.getByRole("heading", { name: "Versión 1" })).toBeVisible();
  await page.getByRole("button", { name: "Editar" }).click();
  await panel(page).getByLabel("Nombre de la variante").fill("Aluminio");
  await panel(page).getByRole("button", { name: "Guardar" }).click();
  await expect(page.getByRole("heading", { name: "Versión 1 · Aluminio" })).toBeVisible();
  await page.getByRole("button", { name: "Nueva sección" }).click();
  await panel(page).getByLabel("Nombre").fill("Colocación");
  await panel(page).getByLabel("IVA").selectOption("10.5");
  await panel(page).getByRole("button", { name: "Crear sección" }).click();
  const general = page.getByRole("region", { name: "General" });
  await general.getByRole("button", { name: "De Catálogo" }).click();
  const cat = panel(page);
  await cat.getByLabel("Designación").fill("V1");
  await cat.getByLabel("Ubicación").fill("Lavadero");
  await cat.getByLabel("Paquete").selectOption({ label: "Zqx197 Ventana opcionales" });
  await cat.getByLabel(/^ancho/).fill("1200");
  await cat.getByLabel(/^alto/).fill("1000");
  await cat.getByRole("button", { name: "Agregar" }).click();
  await expect(cat).toBeHidden();
  await expect(general.getByRole("listitem").filter({ hasText: "V1" })).toBeVisible();
  await cabecera.getByRole("button", { name: "Más acciones" }).click();
  await page.getByRole("button", { name: "Cómo se ven los opcionales…" }).click();
  await panel(page).getByLabel("Mosquitero").selectOption("debajo");
  await panel(page).getByLabel("Zqx197 Colocación").selectOption({ label: "Colocación · ARS · IVA 10,5 %" });
  await panel(page).getByRole("button", { name: "Guardar" }).click();
  await expect(panel(page)).toBeHidden();
  const opcionales = general.getByRole("listitem").filter({ hasText: "V1" }).getByRole("group", { name: "Opcionales" });
  await opcionales.getByRole("checkbox", { name: "Mosquitero" }).check();
  await expect(opcionales.getByText("$ 9.600")).toBeVisible();
  await opcionales.getByRole("button", { name: "Cortina" }).click();
  await expect(opcionales.getByRole("button", { name: "Cortina" })).toHaveAttribute("aria-pressed", "true");
  await opcionales.getByRole("button", { name: "Zqx197 Colocación" }).click();
  await expect(page.getByRole("region", { name: "Colocación" }).getByText("De 1 ventana")).toBeVisible();
  await general.getByRole("button", { name: "A mano" }).click();
  await panel(page).getByLabel("Descripción").fill("Flete cerrado a Pilar");
  await panel(page).getByLabel(/Precio por unidad/).fill("150000");
  await panel(page).getByRole("button", { name: "Agregar" }).click();
  await expect(panel(page)).toBeHidden();
  await publicar();

  // PVC, a partir de Aluminio.
  await page.goto(ficha);
  await tarjeta(page, "Aluminio").getByRole("button", { name: "Más acciones" }).click();
  await page.getByRole("button", { name: "Sumar variante a partir de esta" }).click();
  await expect(page.getByRole("heading", { name: "Versión 2" })).toBeVisible();
  await page.getByRole("button", { name: "Editar" }).click();
  await panel(page).getByLabel("Nombre de la variante").fill("PVC");
  await panel(page).getByRole("button", { name: "Guardar" }).click();
  await expect(panel(page)).toBeHidden();
  await publicar();

  await page.goto(ficha);
  await cabecera.getByRole("link", { name: "Imprimir" }).click();
  await expect(page).toHaveURL(/\/imprimir$/);
  await expect(page.getByRole("heading", { name: `Impreso ${marca}` })).toBeVisible();
  await expect(page.getByText(/^Aluminio \$[\d.]+ · PVC \$[\d.]+$/)).toBeVisible();
  const aluminio = page.getByRole("region", { name: "Aluminio" });
  await expect(aluminio.getByText(/^IVA discriminado · Válido hasta el \d/)).toBeVisible();
  const v1 = aluminio.getByRole("listitem").filter({ hasText: "V1" });
  await expect(v1.getByText("Zqx197 Ventana opcionales · Lavadero")).toBeVisible();
  // Lo cargado, sin el Mosquitero: va en su línea, debajo.
  await expect(v1.getByText("ancho 1200 · alto 1000 · con Cajón · con Cortina", { exact: true })).toBeVisible();
  await expect(v1.getByText("Mosquitero", { exact: true })).toBeVisible();
  await expect(v1.getByText("$ 9.600")).toBeVisible();
  await expect(aluminio.getByRole("listitem").filter({ hasText: "Zqx197 Colocación" }).getByText("De 1 ventana")).toBeVisible();
  await expect(aluminio.getByText("Flete cerrado a Pilar")).toBeVisible();
  await expect(aluminio.getByText("Total", { exact: true })).toBeVisible();
  await expect(page.getByRole("region", { name: "PVC" })).toBeVisible();
  // Nada de lo interno: ni etiquetas del editor ni acciones.
  await expect(page.getByText("A mano", { exact: true })).toHaveCount(0);
  await expect(page.getByRole("main").getByRole("button", { name: "Más acciones" })).toHaveCount(0);
  await page.screenshot({ path: "e2e/.out/pres-impreso.png", fullPage: true });

  // En papel, solo la hoja.
  await page.emulateMedia({ media: "print" });
  await expect(page.getByRole("heading", { name: "Presupuestos", exact: true })).toBeHidden();
  await expect(page.getByRole("button", { name: "Imprimir" })).toBeHidden();
  await expect(page.getByRole("heading", { name: `Impreso ${marca}` })).toBeVisible();
  await page.screenshot({ path: "e2e/.out/pres-impreso-papel.png", fullPage: true });
  await page.pdf({ path: "e2e/.out/pres-impreso.pdf", format: "A4" });
  await page.emulateMedia({ media: "screen" });

  // Aprobado, solo la aprobada.
  await page.goto(ficha);
  await cabecera.getByRole("button", { name: "Aprobar" }).click();
  await dialogo.getByRole("radio", { name: /^PVC/ }).check();
  await dialogo.getByRole("button", { name: "Aprobar" }).click();
  await expect(cabecera.getByText("Aprobado", { exact: true })).toBeVisible();
  await cabecera.getByRole("link", { name: "Imprimir" }).click();
  await expect(page.getByRole("region", { name: "PVC" })).toBeVisible();
  await expect(page.getByRole("region", { name: "Aluminio" })).toHaveCount(0);
  await expect(page.getByText(/^Aluminio \$/)).toHaveCount(0);

  await page.goto(ficha);
  await cabecera.getByRole("button", { name: "Más acciones" }).click();
  await page.getByRole("button", { name: "Revertir…" }).click();
  await dialogo.getByLabel("Por qué se revierte").fill("Prueba del impreso");
  await dialogo.getByRole("button", { name: "Revertir" }).click();
  await expect(cabecera.getByText("Publicado", { exact: true })).toBeVisible();
  await ctx.close();
});

test("la ficha de la obra lista sus presupuestos y arma uno nuevo con la obra puesta", async ({ browser }) => {
  test.setTimeout(120_000);
  const { ctx, page } = await como(browser, "admin");
  const obra = "Edificio Norte Zqx20218 A";
  const primero = `En la obra ${marca}`;
  const segundo = `Desde la obra ${marca}`;

  await page.goto("/presupuestos");
  await page.getByRole("button", { name: "Nuevo presupuesto" }).click();
  const alta = panel(page);
  await alta.getByLabel("Obra").selectOption({ label: obra });
  await alta.getByLabel("Nombre", { exact: true }).fill(primero);
  await alta.getByRole("button", { name: "Crear presupuesto" }).click();
  await expect(page).toHaveURL(/\/presupuestos\/[0-9a-f-]{36}$/);
  await page.getByRole("link", { name: obra }).click();
  await expect(page).toHaveURL(/\/obras\/[0-9a-f-]{36}$/);
  const urlObra = page.url();

  const fila = page.getByRole("link", { name: new RegExp(primero) });
  await expect(fila).toContainText("Borrador");
  await page.screenshot({ path: "e2e/.out/pres-en-obra.png", fullPage: true });

  await page.getByRole("button", { name: "Nuevo presupuesto" }).click();
  const desde = panel(page);
  await expect(desde.getByLabel("Obra")).toBeDisabled();
  await expect(desde.getByLabel("Obra")).toHaveValue(obra);
  await desde.getByLabel("Nombre", { exact: true }).fill(segundo);
  await page.screenshot({ path: "e2e/.out/pres-en-obra-alta.png", fullPage: true });
  await desde.getByRole("button", { name: "Crear presupuesto" }).click();
  await expect(page.getByRole("heading", { name: new RegExp(segundo) })).toBeVisible();

  // El más nuevo, primero; la fila abre su ficha.
  await page.goto(urlObra);
  const filas = page.getByRole("link", { name: new RegExp(`(${primero}|${segundo})`) });
  await expect(filas).toHaveCount(2);
  await expect(filas.first()).toContainText(segundo);
  await filas.last().click();
  await expect(page.getByRole("heading", { name: new RegExp(primero) })).toBeVisible();
  await ctx.close();
});

// Necesita e2e/datos-autorizaciones.sql (plazo). Una obra nueva por corrida: con "Aprobar altas" no entra congelada (OB018).
test("con la obra perdida, el editor lo avisa a quien arma y publicar la reabre", async ({ browser }) => {
  test.setTimeout(180_000);
  const { ctx, page } = await como(browser, "admin");
  await asegurarAprobador(page);
  await page.goto("/obras");
  await page.getByRole("button", { name: "Nueva obra" }).click();
  const alta = panel(page);
  await alta.getByLabel("Nombre", { exact: true }).fill(`Casa Recoleta ${marca}`);
  await alta.getByLabel("Dirección").fill(`Av. Alvear ${marca.slice(3)}`);
  await alta.getByLabel("Tipo de obra").selectOption({ label: "Casa" });
  await alta.getByLabel("Origen").selectOption({ label: "Llamado" });
  const urlObra = await crearIgual(page, alta, "Crear obra", /\/obras\/[0-9a-f-]{36}$/);

  await page.getByTitle("Cambiar estado").click();
  const estado = panel(page);
  await estado.getByLabel("Pasa a").selectOption({ label: "Perdida" });
  await estado.getByLabel("Motivo").selectOption({ label: "Precio" });
  await estado.getByRole("button", { name: "Cambiar" }).click();
  await expect(page.getByRole("button", { name: "Perdida" })).toBeVisible();

  await page.getByRole("button", { name: "Nuevo presupuesto" }).click();
  const desde = panel(page);
  await desde.getByLabel("Nombre", { exact: true }).fill(`Recotizado ${marca}`);
  await desde.getByRole("button", { name: "Crear presupuesto" }).click();
  await page.getByRole("link", { name: /Versión 1/ }).click();
  const aviso = page.getByText("La obra está perdida (precio). Al publicar, se reabre.");
  await expect(aviso).toBeVisible();
  await page.screenshot({ path: "e2e/.out/pres-obra-perdida.png", fullPage: true });

  await page.getByRole("region", { name: "General" }).getByRole("button", { name: "A mano" }).click();
  const mano = panel(page);
  await mano.getByLabel("Descripción").fill("Flete cerrado a Recoleta");
  await mano.getByLabel(/Precio por unidad/).fill("150000");
  await mano.getByRole("button", { name: "Agregar" }).click();
  await expect(mano).toBeHidden();
  await page.getByRole("region", { name: "Antes de publicar" }).getByRole("button", { name: "Publicar" }).click();
  await page.getByRole("dialog").getByRole("button", { name: "Publicar" }).click();
  await expect(page.getByText("Publicada", { exact: true })).toBeVisible();
  await expect(aviso).toHaveCount(0);

  await page.goto(urlObra);
  await expect(page.getByRole("button", { name: "En cotización" })).toBeVisible();
  await ctx.close();
});

// Necesita e2e/datos-autorizaciones.sql (plazo). Una obra nueva por corrida, como la de arriba.
test("en la lista de Obras, una contratada cuenta sus presupuestos publicados, no los borradores", async ({ browser }) => {
  test.setTimeout(180_000);
  const { ctx, page } = await como(browser, "admin");
  await asegurarAprobador(page);
  const obra = `Casa Belgrano ${marca}`;
  await page.goto("/obras");
  await page.getByRole("button", { name: "Nueva obra" }).click();
  const alta = panel(page);
  await alta.getByLabel("Nombre", { exact: true }).fill(obra);
  await alta.getByLabel("Dirección").fill(`Juramento ${marca.slice(3)}`);
  await alta.getByLabel("Tipo de obra").selectOption({ label: "Casa" });
  await alta.getByLabel("Origen").selectOption({ label: "Llamado" });
  const urlObra = await crearIgual(page, alta, "Crear obra", /\/obras\/[0-9a-f-]{36}$/);

  const presupuesto = async (nombrePres: string) => {
    await page.goto(urlObra);
    await page.getByRole("button", { name: "Nuevo presupuesto" }).click();
    const desde = panel(page);
    await desde.getByLabel("Nombre", { exact: true }).fill(nombrePres);
    await desde.getByRole("button", { name: "Crear presupuesto" }).click();
    await expect(page.getByRole("heading", { name: new RegExp(nombrePres) })).toBeVisible();
    const ficha = page.url();
    await page.getByRole("link", { name: /Versión 1/ }).click();
    await page.getByRole("region", { name: "General" }).getByRole("button", { name: "A mano" }).click();
    const mano = panel(page);
    await mano.getByLabel("Descripción").fill("Flete cerrado a Belgrano");
    await mano.getByLabel(/Precio por unidad/).fill("150000");
    await mano.getByRole("button", { name: "Agregar" }).click();
    await expect(mano).toBeHidden();
    return { ficha, version: page.url() };
  };
  const publicar = async () => {
    await page.getByRole("region", { name: "Antes de publicar" }).getByRole("button", { name: "Publicar" }).click();
    await page.getByRole("dialog").getByRole("button", { name: "Publicar" }).click();
    await expect(page.getByText("Publicada", { exact: true })).toBeVisible();
  };
  const fila = async () => {
    await page.goto("/obras");
    await page.getByLabel("Filtrar por estado").selectOption({ label: "Contratadas" });
    await page.getByPlaceholder("Buscar por nombre o dirección…").fill(obra);
    return page.getByRole("link", { name: new RegExp(obra) });
  };

  const etapa1 = await presupuesto(`Etapa 1 ${marca}`);
  await publicar();
  await page.goto(etapa1.ficha);
  await page.locator("div.card").first().getByRole("button", { name: "Aprobar" }).click();
  await page.getByRole("dialog").getByRole("button", { name: "Aprobar" }).click();
  await expect(page.locator("div.card").first().getByText("Aprobado", { exact: true })).toBeVisible();

  // El borrador de la etapa 2 no cuenta: todavía no se mandó.
  const etapa2 = await presupuesto(`Etapa 2 ${marca}`);
  let contratada = await fila();
  await expect(contratada).toContainText("Contratada");
  await expect(contratada).not.toContainText("en cotización");

  await page.goto(etapa2.version);
  await publicar();
  contratada = await fila();
  await expect(contratada).toContainText("1 en cotización");
  await page.screenshot({ path: "e2e/.out/obras-contratada-en-cotizacion.png", fullPage: true });
  await page.setViewportSize({ width: 375, height: 800 });
  await page.screenshot({ path: "e2e/.out/obras-contratada-en-cotizacion-celular.png", fullPage: true });
  await ctx.close();
});

// Necesita e2e/datos-calculadora.sql (un servicio con mínimo). Una obra nueva por corrida, creada desde el panel de alta.
test("la calculadora da el precio y los mínimos, y lleva la ventana a un presupuesto con una obra nueva", async ({ browser }) => {
  test.setTimeout(180_000);
  const { ctx, page } = await como(browser, "admin");
  await asegurarAprobador(page);
  const obra = `Casa Palermo ${marca}`;
  const paquete = "Zqx199 Ventana con mínimo";

  await page.goto("/presupuestos");
  await page.getByRole("link", { name: "Calculadora" }).click();
  await expect(page).toHaveURL(/\/presupuestos\/calculadora$/);
  await page.getByLabel("Paquete").selectOption({ label: paquete });
  const ancho = page.getByLabel(/^ancho/i);
  await ancho.fill("1500");
  await page.getByLabel("Moneda").selectOption("ARS");
  await page.getByRole("button", { name: "Calcular" }).click();
  await expect(page.getByText("$165", { exact: true })).toBeVisible();
  await expect(page.getByText("Mínimo de Zqx199 Colocación")).toBeVisible();
  await expect(page.getByText("+ $49.985")).toBeVisible();
  await expect(page.getByText("$50.150")).toBeVisible();
  await page.screenshot({ path: "e2e/.out/pres-calculadora.png", fullPage: true });

  // Cambiar lo cargado borra el cálculo: lo que se lleva es lo que está a la vista.
  await ancho.fill("1600");
  await expect(page.getByRole("button", { name: "Llevar a un presupuesto" })).toHaveCount(0);
  await ancho.fill("1500");
  await page.getByRole("button", { name: "Calcular" }).click();
  await page.getByRole("button", { name: "Llevar a un presupuesto" }).click();

  const alta = page.getByRole("dialog").filter({ has: page.getByRole("heading", { name: "Nuevo presupuesto" }) });
  await expect(alta.getByText(paquete)).toBeVisible();
  await expect(alta.getByText("$165 sin IVA · cantidad 1")).toBeVisible();
  await alta.getByRole("button", { name: "Nueva obra" }).click();
  const nueva = page.getByRole("dialog").filter({ has: page.getByRole("heading", { name: "Nueva obra" }) });
  await nueva.getByLabel("Nombre", { exact: true }).fill(obra);
  await nueva.getByLabel("Dirección").fill(`Gorriti ${marca.slice(3)}`);
  await nueva.getByLabel("Tipo de obra").selectOption({ label: "Casa" });
  await nueva.getByLabel("Origen").selectOption({ label: "Llamado" });
  await page.screenshot({ path: "e2e/.out/pres-calculadora-obra.png", fullPage: true });
  await nueva.getByRole("button", { name: "Crear obra" }).click();
  const igual = nueva.getByRole("button", { name: "Crear igual" });
  await expect.poll(async () => (await igual.isVisible()) || !(await nueva.isVisible())).toBe(true);
  if (await igual.isVisible()) await igual.click();
  await expect(nueva).toBeHidden();
  await expect(page).toHaveURL(/\/presupuestos\/calculadora$/);
  await expect(alta.getByLabel("Obra").locator("option:checked")).toHaveText(obra);

  await alta.getByLabel("Nombre", { exact: true }).fill(`Ventana ${marca}`);
  await page.screenshot({ path: "e2e/.out/pres-calculadora-alta.png", fullPage: true });
  await alta.getByRole("button", { name: "Crear presupuesto" }).click();
  await expect(page).toHaveURL(/\/presupuestos\/[0-9a-f-]{36}\/[0-9a-f-]{36}$/);
  const general = page.getByRole("region", { name: "General" });
  await expect(general.getByRole("listitem").filter({ hasText: paquete })).toBeVisible();
  await expect(general.getByRole("listitem").filter({ hasText: "Zqx199 Colocación" })).toContainText("Mínimo");
  await page.screenshot({ path: "e2e/.out/pres-calculadora-editor.png", fullPage: true });
  await page.goto("/presupuestos/calculadora");
  await page.setViewportSize({ width: 375, height: 800 });
  await page.screenshot({ path: "e2e/.out/pres-calculadora-celular.png", fullPage: true });
  await ctx.close();
});
