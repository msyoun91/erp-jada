import { notFound } from "next/navigation";
import { puedeCrearObra, puedeTransferir, puedeVerObras } from "@/modules/obras/permissions";
import { getObras } from "@/modules/obras/queries";
import { ObrasView } from "@/modules/obras/components/ObrasView";

export default async function ObrasPage() {
  if (!(await puedeVerObras())) notFound();

  const [obras, crear, transferir] = await Promise.all([
    getObras(),
    puedeCrearObra(),
    puedeTransferir(),
  ]);

  return <ObrasView obras={obras} puedeCrear={crear} puedeTransferir={transferir} />;
}
