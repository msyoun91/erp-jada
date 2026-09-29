import { test, expect } from "@playwright/test";
import { como, panel } from "./comun";

// Tramo 5 de Tareas: Juan (tester) arma una plantilla sobre la obra con un paso
// que se completa solo al vincular un arquitecto. Todo lleva el marcador.
const marca = `Zqx${Date.now() % 100000}`;
const plantilla = `Seguimiento de obra ${marca}`;

test.describe.configure({ mode: "serial" });

test("Juan arma una plantilla sobre la obra que corre sola", async ({ browser }) => {
  const { ctx, page } = await como(browser, "tester");
  await page.goto("/tareas/plantillas");
  await page.getByRole("button", { name: "Nueva plantilla" }).click();
  const form = panel(page);
  await form.getByLabel("Nombre").fill(plantilla);
  await form.getByLabel("Sobre").selectOption({ label: "Obra" });
  await form.getByLabel("Corre sola").selectOption({ label: "Al pasar a Contratada" });
  await form.getByRole("checkbox", { name: "Activa" }).check();

  await form.getByLabel("Título", { exact: true }).fill("Vincular arquitecto");
  await form.getByRole("button", { name: "+ Obra" }).click();
  await expect(form.getByLabel("Descripción").nth(1)).toHaveValue("{@registro}");
  await form.getByLabel("Se completa").selectOption({ label: "Al vincular arquitecto" });

  await form.getByRole("button", { name: "Sumar paso" }).click();
  await form.getByLabel("Título", { exact: true }).nth(1).fill("Coordinar con el arquitecto");
  await form.getByRole("group", { name: "Insertar en la descripción" }).nth(1).getByRole("button", { name: "+ Arquitecto" }).click();
  await form.getByLabel("Entra").nth(1).selectOption({ label: "Si hay arquitecto" });

  await form.getByRole("button", { name: "Crear plantilla" }).click();
  await expect(form).toBeHidden();

  const card = page.locator("div.card").filter({ hasText: plantilla });
  await expect(card).toContainText("Sobre: Obra");
  await expect(card).toContainText("Al pasar a Contratada");
  await card.getByText("Ver pasos").click();
  await expect(card).toContainText("Se completa sola al vincular arquitecto");
  await expect(card).toContainText("Si hay arquitecto");

  await card.getByRole("button", { name: "Más acciones" }).click();
  await page.getByRole("button", { name: "Editar" }).click();
  const editar = panel(page);
  await expect(editar.getByLabel("Sobre")).toHaveValue("obra");
  await expect(editar.getByLabel("Corre sola")).toHaveValue("estado:contratada");
  await expect(editar.getByRole("checkbox", { name: "Activa" })).toBeChecked();
  await expect(editar.getByLabel("Se completa").first()).toHaveValue("relacion_alta:arquitecto");
  await expect(editar.getByLabel("Entra").nth(1)).toHaveValue("arquitecto");
  await editar.getByRole("button", { name: "Cancelar" }).click();
  await ctx.close();
});
