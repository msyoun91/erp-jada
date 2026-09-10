import { notFound } from "next/navigation";
import { puedeCrearObra, puedeTransferir, puedeVerObras } from "@/modules/obras/permissions";
import { getObras } from "@/modules/obras/queries";
import { ObrasView } from "@/modules/obras/components/ObrasView";

export default async function ObrasPage({
  searchParams,
}: {
  searchParams: Promise<{ alcance?: string }>;
}) {
  if (!(await puedeVerObras())) notFound();

  const { alcance: alcanceParam } = await searchParams;
  const alcance = alcanceParam === "todos" ? "todos" : "propios";

  const [obras, crear, transferir] = await Promise.all([
    getObras({ alcance }),
    puedeCrearObra(),
    puedeTransferir(),
  ]);

  return <ObrasView obras={obras} puedeCrear={crear} puedeTransferir={transferir} />;
}
