import { notFound } from "next/navigation";
import {
  puedeCrearPersona,
  puedeVerPersonas,
  puedeVerTodasLasPersonas,
} from "@/modules/obras/permissions";
import { getPersonas, getUsuarioActualId } from "@/modules/obras/queries";
import { PersonasView } from "@/modules/obras/components/PersonasView";

export default async function PersonasPage({
  searchParams,
}: {
  searchParams: Promise<{ alcance?: string }>;
}) {
  if (!(await puedeVerPersonas())) notFound();

  const { alcance: alcanceParam } = await searchParams;
  const alcance = alcanceParam === "todos" ? "todos" : "propios";

  const [personas, crear, todas, miId] = await Promise.all([
    getPersonas(undefined, alcance),
    puedeCrearPersona(),
    puedeVerTodasLasPersonas(),
    getUsuarioActualId(),
  ]);

  return (
    <PersonasView personas={personas} puedeCrear={crear} veTodas={todas} miId={miId} />
  );
}
