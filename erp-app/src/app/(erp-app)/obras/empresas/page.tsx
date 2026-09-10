import { notFound } from "next/navigation";
import {
  puedeCrearEmpresa,
  puedeVerEmpresas,
  puedeVerTodasLasEmpresas,
} from "@/modules/obras/permissions";
import { getEmpresas } from "@/modules/obras/queries";
import { EmpresasView } from "@/modules/obras/components/EmpresasView";

export default async function EmpresasPage({
  searchParams,
}: {
  searchParams: Promise<{ alcance?: string }>;
}) {
  if (!(await puedeVerEmpresas())) notFound();

  const { alcance: alcanceParam } = await searchParams;
  const alcance = alcanceParam === "todos" ? "todos" : "propios";

  const [empresas, crear, veTodas] = await Promise.all([
    getEmpresas(undefined, alcance),
    puedeCrearEmpresa(),
    puedeVerTodasLasEmpresas(),
  ]);

  return <EmpresasView empresas={empresas} puedeCrear={crear} veTodas={veTodas} />;
}
