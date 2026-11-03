import { notFound, redirect } from "next/navigation";
import { pestanasCatalogo } from "@/modules/catalogo/pestanas";

// Sin `catalogo_ver`: cada pestaña tiene su código, y /catalogo abre la primera que el usuario tiene.
export default async function CatalogoPage() {
  const [primera] = await pestanasCatalogo();
  if (!primera) notFound();
  redirect(primera.href);
}
