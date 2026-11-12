import type { GuionTutorial } from "@/components/layout/Tutorial";

export const TUTORIAL_MONEDAS: GuionTutorial = {
  "/monedas": [
    {
      codigo: "monedas_ver_principal",
      titulo: "La moneda en la que se piensa",
      texto:
        "Viene elegida en un presupuesto nuevo y al cargar un monto, y los totales se muestran en ella. Cada monto guarda su propia moneda: cambiarla no reescribe lo cargado.",
    },
    {
      codigo: "monedas_ver_tarjetas",
      titulo: "Un valor por día, para todo el ERP",
      texto:
        "Los tipos de cambio se traen solos de MonedAPI. Cada monto se convierte con el valor de su fecha, por eso el historial importa. «Corregir» carga un valor a mano.",
    },
    {
      codigo: "monedas_ver_pendiente",
      titulo: "Un salto grande espera tu OK",
      texto:
        "Si MonedAPI trae un valor que se mueve 50 % o más contra el anterior, no rige hasta que alguien lo confirme o lo corrija. Mientras tanto, todo sigue con el vigente.",
    },
  ],
};
