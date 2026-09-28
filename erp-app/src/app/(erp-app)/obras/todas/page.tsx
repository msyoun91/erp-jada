import { notFound } from "next/navigation";
import { getUsuarioActualId } from "@/lib/usuarios";
import { puedeVerTodas } from "@/modules/obras/permissions";
import { getNombres, getObras } from "@/modules/obras/queries";
import { ObrasView } from "@/modules/obras/components/ObrasView";

// Todas, también las desactivadas; sin alta, que una obra nueva es de quien la carga.
export default async function TodasPage() {
  const yo = await getUsuarioActualId();
  if (!yo || !(await puedeVerTodas())) notFound();

  const [obras, nombres] = await Promise.all([getObras({ inactivas: true }), getNombres()]);

  return <ObrasView obras={obras} yo={yo} nombres={nombres} />;
}
