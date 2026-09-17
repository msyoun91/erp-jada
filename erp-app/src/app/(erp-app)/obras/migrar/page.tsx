import { notFound } from "next/navigation";
import { puedeMigrarAgenda } from "@/modules/obras/permissions";
import { getUsuariosParaTransferir } from "@/modules/obras/queries";
import { MigrarAgendaView } from "@/modules/obras/components/MigrarAgendaView";

export default async function ObrasMigrarPage() {
  if (!(await puedeMigrarAgenda())) notFound();

  return <MigrarAgendaView usuarios={await getUsuariosParaTransferir()} />;
}
