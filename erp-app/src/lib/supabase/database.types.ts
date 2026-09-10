export type Json =
  | string
  | number
  | boolean
  | null
  | { [key: string]: Json | undefined }
  | Json[];

export type Database = {
  // Allows to automatically instantiate createClient with right options
  // instead of createClient<Database, { PostgrestVersion: 'XX' }>(URL, KEY)
  __InternalSupabase: {
    PostgrestVersion: "14.5";
  };
  public: {
    Tables: {
      obras: {
        Row: {
          activo: boolean;
          created_at: string;
          detalle_perdida: string | null;
          direccion: string | null;
          direccion_norm: string | null;
          estado: Database["public"]["Enums"]["estado_obra"];
          id: string;
          localidad: string | null;
          localidad_norm: string | null;
          motivo_perdida: Database["public"]["Enums"]["motivo_perdida"] | null;
          motivo_rechazo: string | null;
          nombre: string;
          nombre_norm: string | null;
          observaciones: string | null;
          origen: Database["public"]["Enums"]["origen_obra"] | null;
          pendiente: boolean;
          provincia: Database["public"]["Enums"]["provincia"] | null;
          responsable_id: string;
          tipo: Database["public"]["Enums"]["tipo_obra"];
          updated_at: string;
        };
        Insert: {
          activo?: boolean;
          created_at?: string;
          detalle_perdida?: string | null;
          direccion?: string | null;
          direccion_norm?: string | null;
          estado?: Database["public"]["Enums"]["estado_obra"];
          id?: string;
          localidad?: string | null;
          localidad_norm?: string | null;
          motivo_perdida?: Database["public"]["Enums"]["motivo_perdida"] | null;
          motivo_rechazo?: string | null;
          nombre: string;
          nombre_norm?: string | null;
          observaciones?: string | null;
          origen?: Database["public"]["Enums"]["origen_obra"] | null;
          pendiente?: boolean;
          provincia?: Database["public"]["Enums"]["provincia"] | null;
          responsable_id: string;
          tipo: Database["public"]["Enums"]["tipo_obra"];
          updated_at?: string;
        };
        Update: {
          activo?: boolean;
          created_at?: string;
          detalle_perdida?: string | null;
          direccion?: string | null;
          direccion_norm?: string | null;
          estado?: Database["public"]["Enums"]["estado_obra"];
          id?: string;
          localidad?: string | null;
          localidad_norm?: string | null;
          motivo_perdida?: Database["public"]["Enums"]["motivo_perdida"] | null;
          motivo_rechazo?: string | null;
          nombre?: string;
          nombre_norm?: string | null;
          observaciones?: string | null;
          origen?: Database["public"]["Enums"]["origen_obra"] | null;
          pendiente?: boolean;
          provincia?: Database["public"]["Enums"]["provincia"] | null;
          responsable_id?: string;
          tipo?: Database["public"]["Enums"]["tipo_obra"];
          updated_at?: string;
        };
        Relationships: [
          {
            foreignKeyName: "obras_responsable_id_fkey";
            columns: ["responsable_id"];
            isOneToOne: false;
            referencedRelation: "usuarios";
            referencedColumns: ["id"];
          },
        ];
      };
      obras_accesos_persona: {
        Row: {
          contexto: string | null;
          created_at: string;
          id: string;
          persona_id: string;
          usuario_id: string;
        };
        Insert: {
          contexto?: string | null;
          created_at?: string;
          id?: string;
          persona_id: string;
          usuario_id: string;
        };
        Update: {
          contexto?: string | null;
          created_at?: string;
          id?: string;
          persona_id?: string;
          usuario_id?: string;
        };
        Relationships: [
          {
            foreignKeyName: "obras_accesos_persona_persona_id_fkey";
            columns: ["persona_id"];
            isOneToOne: false;
            referencedRelation: "obras_personas";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "obras_accesos_persona_usuario_id_fkey";
            columns: ["usuario_id"];
            isOneToOne: false;
            referencedRelation: "usuarios";
            referencedColumns: ["id"];
          },
        ];
      };
      obras_aprobaciones: {
        Row: {
          aprobada: boolean;
          created_at: string;
          decidido_por: string;
          etiqueta: string;
          id: string;
          motivo: string | null;
          registro_id: string;
          tipo: string;
        };
        Insert: {
          aprobada: boolean;
          created_at?: string;
          decidido_por: string;
          etiqueta: string;
          id?: string;
          motivo?: string | null;
          registro_id: string;
          tipo: string;
        };
        Update: {
          aprobada?: boolean;
          created_at?: string;
          decidido_por?: string;
          etiqueta?: string;
          id?: string;
          motivo?: string | null;
          registro_id?: string;
          tipo?: string;
        };
        Relationships: [
          {
            foreignKeyName: "obras_aprobaciones_decidido_por_fkey";
            columns: ["decidido_por"];
            isOneToOne: false;
            referencedRelation: "usuarios";
            referencedColumns: ["id"];
          },
        ];
      };
      obras_empresa_compartida: {
        Row: {
          activo: boolean;
          created_at: string;
          empresa_id: string;
          id: string;
          origen_obra_id: string | null;
          otorgada_por: string;
          updated_at: string;
          usuario_id: string;
        };
        Insert: {
          activo?: boolean;
          created_at?: string;
          empresa_id: string;
          id?: string;
          origen_obra_id?: string | null;
          otorgada_por: string;
          updated_at?: string;
          usuario_id: string;
        };
        Update: {
          activo?: boolean;
          created_at?: string;
          empresa_id?: string;
          id?: string;
          origen_obra_id?: string | null;
          otorgada_por?: string;
          updated_at?: string;
          usuario_id?: string;
        };
        Relationships: [
          {
            foreignKeyName: "obras_empresa_compartida_empresa_id_fkey";
            columns: ["empresa_id"];
            isOneToOne: false;
            referencedRelation: "obras_empresas";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "obras_empresa_compartida_origen_obra_id_fkey";
            columns: ["origen_obra_id"];
            isOneToOne: false;
            referencedRelation: "obras";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "obras_empresa_compartida_otorgada_por_fkey";
            columns: ["otorgada_por"];
            isOneToOne: false;
            referencedRelation: "usuarios";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "obras_empresa_compartida_usuario_id_fkey";
            columns: ["usuario_id"];
            isOneToOne: false;
            referencedRelation: "usuarios";
            referencedColumns: ["id"];
          },
        ];
      };
      obras_empresas: {
        Row: {
          activo: boolean;
          creado_por: string;
          created_at: string;
          direccion: string | null;
          email: string | null;
          id: string;
          localidad: string | null;
          motivo_rechazo: string | null;
          nombre_comercial: string | null;
          nombre_comercial_norm: string | null;
          observaciones: string | null;
          pendiente: boolean;
          provincia: Database["public"]["Enums"]["provincia"] | null;
          razon_social: string;
          razon_social_norm: string | null;
          telefono: string | null;
          updated_at: string;
          website: string | null;
        };
        Insert: {
          activo?: boolean;
          creado_por: string;
          created_at?: string;
          direccion?: string | null;
          email?: string | null;
          id?: string;
          localidad?: string | null;
          motivo_rechazo?: string | null;
          nombre_comercial?: string | null;
          nombre_comercial_norm?: string | null;
          observaciones?: string | null;
          pendiente?: boolean;
          provincia?: Database["public"]["Enums"]["provincia"] | null;
          razon_social: string;
          razon_social_norm?: string | null;
          telefono?: string | null;
          updated_at?: string;
          website?: string | null;
        };
        Update: {
          activo?: boolean;
          creado_por?: string;
          created_at?: string;
          direccion?: string | null;
          email?: string | null;
          id?: string;
          localidad?: string | null;
          motivo_rechazo?: string | null;
          nombre_comercial?: string | null;
          nombre_comercial_norm?: string | null;
          observaciones?: string | null;
          pendiente?: boolean;
          provincia?: Database["public"]["Enums"]["provincia"] | null;
          razon_social?: string;
          razon_social_norm?: string | null;
          telefono?: string | null;
          updated_at?: string;
          website?: string | null;
        };
        Relationships: [
          {
            foreignKeyName: "obras_empresas_creado_por_fkey";
            columns: ["creado_por"];
            isOneToOne: false;
            referencedRelation: "usuarios";
            referencedColumns: ["id"];
          },
        ];
      };
      obras_obra_compartida: {
        Row: {
          activo: boolean | null;
          created_at: string | null;
          id: string;
          obra_id: string;
          otorgada_por: string;
          updated_at: string | null;
          usuario_id: string;
        };
        Insert: {
          activo?: boolean | null;
          created_at?: string | null;
          id?: string;
          obra_id: string;
          otorgada_por: string;
          updated_at?: string | null;
          usuario_id: string;
        };
        Update: {
          activo?: boolean | null;
          created_at?: string | null;
          id?: string;
          obra_id?: string;
          otorgada_por?: string;
          updated_at?: string | null;
          usuario_id?: string;
        };
        Relationships: [
          {
            foreignKeyName: "obras_obra_compartida_obra_id_fkey";
            columns: ["obra_id"];
            isOneToOne: false;
            referencedRelation: "obras";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "obras_obra_compartida_otorgada_por_fkey";
            columns: ["otorgada_por"];
            isOneToOne: false;
            referencedRelation: "usuarios";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "obras_obra_compartida_usuario_id_fkey";
            columns: ["usuario_id"];
            isOneToOne: false;
            referencedRelation: "usuarios";
            referencedColumns: ["id"];
          },
        ];
      };
      obras_obra_empresa: {
        Row: {
          activo: boolean;
          created_at: string;
          empresa_id: string;
          id: string;
          obra_id: string;
          observaciones: string | null;
          roles: Database["public"]["Enums"]["rol_empresa"][];
          updated_at: string;
        };
        Insert: {
          activo?: boolean;
          created_at?: string;
          empresa_id: string;
          id?: string;
          obra_id: string;
          observaciones?: string | null;
          roles: Database["public"]["Enums"]["rol_empresa"][];
          updated_at?: string;
        };
        Update: {
          activo?: boolean;
          created_at?: string;
          empresa_id?: string;
          id?: string;
          obra_id?: string;
          observaciones?: string | null;
          roles?: Database["public"]["Enums"]["rol_empresa"][];
          updated_at?: string;
        };
        Relationships: [
          {
            foreignKeyName: "obras_obra_empresa_empresa_id_fkey";
            columns: ["empresa_id"];
            isOneToOne: false;
            referencedRelation: "obras_empresas";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "obras_obra_empresa_obra_id_fkey";
            columns: ["obra_id"];
            isOneToOne: false;
            referencedRelation: "obras";
            referencedColumns: ["id"];
          },
        ];
      };
      obras_obra_persona: {
        Row: {
          activo: boolean;
          created_at: string;
          empresa_id: string | null;
          id: string;
          obra_id: string;
          observaciones: string | null;
          persona_id: string;
          roles: Database["public"]["Enums"]["rol_persona"][];
          updated_at: string;
        };
        Insert: {
          activo?: boolean;
          created_at?: string;
          empresa_id?: string | null;
          id?: string;
          obra_id: string;
          observaciones?: string | null;
          persona_id: string;
          roles: Database["public"]["Enums"]["rol_persona"][];
          updated_at?: string;
        };
        Update: {
          activo?: boolean;
          created_at?: string;
          empresa_id?: string | null;
          id?: string;
          obra_id?: string;
          observaciones?: string | null;
          persona_id?: string;
          roles?: Database["public"]["Enums"]["rol_persona"][];
          updated_at?: string;
        };
        Relationships: [
          {
            foreignKeyName: "obras_obra_persona_empresa_id_fkey";
            columns: ["empresa_id"];
            isOneToOne: false;
            referencedRelation: "obras_empresas";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "obras_obra_persona_obra_id_fkey";
            columns: ["obra_id"];
            isOneToOne: false;
            referencedRelation: "obras";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "obras_obra_persona_persona_id_fkey";
            columns: ["persona_id"];
            isOneToOne: false;
            referencedRelation: "obras_personas";
            referencedColumns: ["id"];
          },
        ];
      };
      obras_obra_referente: {
        Row: {
          activo: boolean;
          created_at: string;
          id: string;
          obra_id: string;
          observaciones: string | null;
          persona_id: string;
          porcentaje_comision: number;
          updated_at: string;
        };
        Insert: {
          activo?: boolean;
          created_at?: string;
          id?: string;
          obra_id: string;
          observaciones?: string | null;
          persona_id: string;
          porcentaje_comision: number;
          updated_at?: string;
        };
        Update: {
          activo?: boolean;
          created_at?: string;
          id?: string;
          obra_id?: string;
          observaciones?: string | null;
          persona_id?: string;
          porcentaje_comision?: number;
          updated_at?: string;
        };
        Relationships: [
          {
            foreignKeyName: "obras_obra_referente_obra_id_fkey";
            columns: ["obra_id"];
            isOneToOne: false;
            referencedRelation: "obras";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "obras_obra_referente_persona_id_fkey";
            columns: ["persona_id"];
            isOneToOne: false;
            referencedRelation: "obras_personas";
            referencedColumns: ["id"];
          },
        ];
      };
      obras_persona_compartida: {
        Row: {
          activo: boolean;
          created_at: string;
          id: string;
          origen_empresa_id: string | null;
          origen_obra_id: string | null;
          otorgada_por: string;
          persona_id: string;
          updated_at: string;
          usuario_id: string;
        };
        Insert: {
          activo?: boolean;
          created_at?: string;
          id?: string;
          origen_empresa_id?: string | null;
          origen_obra_id?: string | null;
          otorgada_por: string;
          persona_id: string;
          updated_at?: string;
          usuario_id: string;
        };
        Update: {
          activo?: boolean;
          created_at?: string;
          id?: string;
          origen_empresa_id?: string | null;
          origen_obra_id?: string | null;
          otorgada_por?: string;
          persona_id?: string;
          updated_at?: string;
          usuario_id?: string;
        };
        Relationships: [
          {
            foreignKeyName: "obras_persona_compartida_origen_empresa_id_fkey";
            columns: ["origen_empresa_id"];
            isOneToOne: false;
            referencedRelation: "obras_empresas";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "obras_persona_compartida_origen_obra_id_fkey";
            columns: ["origen_obra_id"];
            isOneToOne: false;
            referencedRelation: "obras";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "obras_persona_compartida_otorgada_por_fkey";
            columns: ["otorgada_por"];
            isOneToOne: false;
            referencedRelation: "usuarios";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "obras_persona_compartida_persona_id_fkey";
            columns: ["persona_id"];
            isOneToOne: false;
            referencedRelation: "obras_personas";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "obras_persona_compartida_usuario_id_fkey";
            columns: ["usuario_id"];
            isOneToOne: false;
            referencedRelation: "usuarios";
            referencedColumns: ["id"];
          },
        ];
      };
      obras_persona_empresa: {
        Row: {
          activo: boolean;
          cargo: string | null;
          created_at: string;
          empresa_id: string;
          es_principal: boolean;
          id: string;
          observaciones: string | null;
          persona_id: string;
          updated_at: string;
        };
        Insert: {
          activo?: boolean;
          cargo?: string | null;
          created_at?: string;
          empresa_id: string;
          es_principal?: boolean;
          id?: string;
          observaciones?: string | null;
          persona_id: string;
          updated_at?: string;
        };
        Update: {
          activo?: boolean;
          cargo?: string | null;
          created_at?: string;
          empresa_id?: string;
          es_principal?: boolean;
          id?: string;
          observaciones?: string | null;
          persona_id?: string;
          updated_at?: string;
        };
        Relationships: [
          {
            foreignKeyName: "obras_persona_empresa_empresa_id_fkey";
            columns: ["empresa_id"];
            isOneToOne: false;
            referencedRelation: "obras_empresas";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "obras_persona_empresa_persona_id_fkey";
            columns: ["persona_id"];
            isOneToOne: false;
            referencedRelation: "obras_personas";
            referencedColumns: ["id"];
          },
        ];
      };
      obras_persona_grant_contextual: {
        Row: {
          activo: boolean;
          created_at: string;
          empresa_id: string | null;
          id: string;
          obra_id: string | null;
          otorgada_por: string;
          persona_id: string;
          updated_at: string;
          usuario_id: string;
        };
        Insert: {
          activo?: boolean;
          created_at?: string;
          empresa_id?: string | null;
          id?: string;
          obra_id?: string | null;
          otorgada_por: string;
          persona_id: string;
          updated_at?: string;
          usuario_id: string;
        };
        Update: {
          activo?: boolean;
          created_at?: string;
          empresa_id?: string | null;
          id?: string;
          obra_id?: string | null;
          otorgada_por?: string;
          persona_id?: string;
          updated_at?: string;
          usuario_id?: string;
        };
        Relationships: [
          {
            foreignKeyName: "obras_persona_grant_contextual_empresa_id_fkey";
            columns: ["empresa_id"];
            isOneToOne: false;
            referencedRelation: "obras_empresas";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "obras_persona_grant_contextual_obra_id_fkey";
            columns: ["obra_id"];
            isOneToOne: false;
            referencedRelation: "obras";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "obras_persona_grant_contextual_otorgada_por_fkey";
            columns: ["otorgada_por"];
            isOneToOne: false;
            referencedRelation: "usuarios";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "obras_persona_grant_contextual_persona_id_fkey";
            columns: ["persona_id"];
            isOneToOne: false;
            referencedRelation: "obras_personas";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "obras_persona_grant_contextual_usuario_id_fkey";
            columns: ["usuario_id"];
            isOneToOne: false;
            referencedRelation: "usuarios";
            referencedColumns: ["id"];
          },
        ];
      };
      obras_personas: {
        Row: {
          activo: boolean;
          apellido: string | null;
          creado_por: string;
          created_at: string;
          email: string | null;
          email_norm: string | null;
          id: string;
          motivo_rechazo: string | null;
          nombre: string;
          nombre_norm: string | null;
          observaciones: string | null;
          pendiente: boolean;
          telefono: string | null;
          telefono_norm: string | null;
          updated_at: string;
          whatsapp: string | null;
          whatsapp_norm: string | null;
        };
        Insert: {
          activo?: boolean;
          apellido?: string | null;
          creado_por: string;
          created_at?: string;
          email?: string | null;
          email_norm?: string | null;
          id?: string;
          motivo_rechazo?: string | null;
          nombre: string;
          nombre_norm?: string | null;
          observaciones?: string | null;
          pendiente?: boolean;
          telefono?: string | null;
          telefono_norm?: string | null;
          updated_at?: string;
          whatsapp?: string | null;
          whatsapp_norm?: string | null;
        };
        Update: {
          activo?: boolean;
          apellido?: string | null;
          creado_por?: string;
          created_at?: string;
          email?: string | null;
          email_norm?: string | null;
          id?: string;
          motivo_rechazo?: string | null;
          nombre?: string;
          nombre_norm?: string | null;
          observaciones?: string | null;
          pendiente?: boolean;
          telefono?: string | null;
          telefono_norm?: string | null;
          updated_at?: string;
          whatsapp?: string | null;
          whatsapp_norm?: string | null;
        };
        Relationships: [
          {
            foreignKeyName: "obras_personas_creado_por_fkey";
            columns: ["creado_por"];
            isOneToOne: false;
            referencedRelation: "usuarios";
            referencedColumns: ["id"];
          },
        ];
      };
      obras_transferencias: {
        Row: {
          a_usuario_id: string;
          created_at: string;
          de_usuario_id: string;
          ejecutada_por: string;
          empresa_id: string | null;
          id: string;
          obra_id: string | null;
          persona_id: string | null;
          tipo: string;
        };
        Insert: {
          a_usuario_id: string;
          created_at?: string;
          de_usuario_id: string;
          ejecutada_por: string;
          empresa_id?: string | null;
          id?: string;
          obra_id?: string | null;
          persona_id?: string | null;
          tipo?: string;
        };
        Update: {
          a_usuario_id?: string;
          created_at?: string;
          de_usuario_id?: string;
          ejecutada_por?: string;
          empresa_id?: string | null;
          id?: string;
          obra_id?: string | null;
          persona_id?: string | null;
          tipo?: string;
        };
        Relationships: [
          {
            foreignKeyName: "obras_transferencias_a_usuario_id_fkey";
            columns: ["a_usuario_id"];
            isOneToOne: false;
            referencedRelation: "usuarios";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "obras_transferencias_de_usuario_id_fkey";
            columns: ["de_usuario_id"];
            isOneToOne: false;
            referencedRelation: "usuarios";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "obras_transferencias_ejecutada_por_fkey";
            columns: ["ejecutada_por"];
            isOneToOne: false;
            referencedRelation: "usuarios";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "obras_transferencias_empresa_id_fkey";
            columns: ["empresa_id"];
            isOneToOne: false;
            referencedRelation: "obras_empresas";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "obras_transferencias_obra_id_fkey";
            columns: ["obra_id"];
            isOneToOne: false;
            referencedRelation: "obras";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "obras_transferencias_persona_id_fkey";
            columns: ["persona_id"];
            isOneToOne: false;
            referencedRelation: "obras_personas";
            referencedColumns: ["id"];
          },
        ];
      };
      submodulos: {
        Row: {
          activo: boolean;
          codigo: string;
          created_at: string;
          id: string;
          modulo: string;
          nombre: string;
          orden: number;
          tipo: Database["public"]["Enums"]["tipo_submodulo"];
          updated_at: string;
          vista_id: string | null;
        };
        Insert: {
          activo?: boolean;
          codigo: string;
          created_at?: string;
          id?: string;
          modulo: string;
          nombre: string;
          orden?: number;
          tipo: Database["public"]["Enums"]["tipo_submodulo"];
          updated_at?: string;
          vista_id?: string | null;
        };
        Update: {
          activo?: boolean;
          codigo?: string;
          created_at?: string;
          id?: string;
          modulo?: string;
          nombre?: string;
          orden?: number;
          tipo?: Database["public"]["Enums"]["tipo_submodulo"];
          updated_at?: string;
          vista_id?: string | null;
        };
        Relationships: [
          {
            foreignKeyName: "submodulos_vista_id_fkey";
            columns: ["vista_id"];
            isOneToOne: false;
            referencedRelation: "submodulos";
            referencedColumns: ["id"];
          },
        ];
      };
      tareas: {
        Row: {
          activo: boolean;
          creado_por: string;
          created_at: string;
          descripcion: string | null;
          estado: Database["public"]["Enums"]["estado_tarea"];
          fecha_vencimiento: string | null;
          hilo_id: string | null;
          id: string;
          modo_completado: Database["public"]["Enums"]["modo_completado"];
          nota_anterior: string | null;
          nota_siguiente: string | null;
          origen_app: string | null;
          origen_punto: string | null;
          paso_anterior_id: string | null;
          posponer_desde: string | null;
          posponer_hasta: string | null;
          proyecto_id: string | null;
          recurrencia_cantidad: number | null;
          recurrencia_unidad:
            Database["public"]["Enums"]["recurrencia_unidad"] | null;
          responsable_id: string;
          temperatura: number;
          titulo: string;
          updated_at: string;
          visibilidad: Database["public"]["Enums"]["visibilidad"];
        };
        Insert: {
          activo?: boolean;
          creado_por: string;
          created_at?: string;
          descripcion?: string | null;
          estado?: Database["public"]["Enums"]["estado_tarea"];
          fecha_vencimiento?: string | null;
          hilo_id?: string | null;
          id?: string;
          modo_completado?: Database["public"]["Enums"]["modo_completado"];
          nota_anterior?: string | null;
          nota_siguiente?: string | null;
          origen_app?: string | null;
          origen_punto?: string | null;
          paso_anterior_id?: string | null;
          posponer_desde?: string | null;
          posponer_hasta?: string | null;
          proyecto_id?: string | null;
          recurrencia_cantidad?: number | null;
          recurrencia_unidad?:
            Database["public"]["Enums"]["recurrencia_unidad"] | null;
          responsable_id: string;
          temperatura?: number;
          titulo: string;
          updated_at?: string;
          visibilidad?: Database["public"]["Enums"]["visibilidad"];
        };
        Update: {
          activo?: boolean;
          creado_por?: string;
          created_at?: string;
          descripcion?: string | null;
          estado?: Database["public"]["Enums"]["estado_tarea"];
          fecha_vencimiento?: string | null;
          hilo_id?: string | null;
          id?: string;
          modo_completado?: Database["public"]["Enums"]["modo_completado"];
          nota_anterior?: string | null;
          nota_siguiente?: string | null;
          origen_app?: string | null;
          origen_punto?: string | null;
          paso_anterior_id?: string | null;
          posponer_desde?: string | null;
          posponer_hasta?: string | null;
          proyecto_id?: string | null;
          recurrencia_cantidad?: number | null;
          recurrencia_unidad?:
            Database["public"]["Enums"]["recurrencia_unidad"] | null;
          responsable_id?: string;
          temperatura?: number;
          titulo?: string;
          updated_at?: string;
          visibilidad?: Database["public"]["Enums"]["visibilidad"];
        };
        Relationships: [
          {
            foreignKeyName: "tareas_creado_por_fkey";
            columns: ["creado_por"];
            isOneToOne: false;
            referencedRelation: "usuarios";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "tareas_hilo_id_fkey";
            columns: ["hilo_id"];
            isOneToOne: false;
            referencedRelation: "tareas_hilos";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "tareas_paso_anterior_id_fkey";
            columns: ["paso_anterior_id"];
            isOneToOne: false;
            referencedRelation: "tareas";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "tareas_proyecto_id_fkey";
            columns: ["proyecto_id"];
            isOneToOne: false;
            referencedRelation: "tareas_proyectos";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "tareas_responsable_id_fkey";
            columns: ["responsable_id"];
            isOneToOne: false;
            referencedRelation: "usuarios";
            referencedColumns: ["id"];
          },
        ];
      };
      tareas_asignados: {
        Row: {
          activo: boolean;
          created_at: string;
          id: string;
          tarea_id: string;
          usuario_id: string;
        };
        Insert: {
          activo?: boolean;
          created_at?: string;
          id?: string;
          tarea_id: string;
          usuario_id: string;
        };
        Update: {
          activo?: boolean;
          created_at?: string;
          id?: string;
          tarea_id?: string;
          usuario_id?: string;
        };
        Relationships: [
          {
            foreignKeyName: "tareas_asignados_tarea_id_fkey";
            columns: ["tarea_id"];
            isOneToOne: false;
            referencedRelation: "tareas";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "tareas_asignados_usuario_id_fkey";
            columns: ["usuario_id"];
            isOneToOne: false;
            referencedRelation: "usuarios";
            referencedColumns: ["id"];
          },
        ];
      };
      tareas_eventos: {
        Row: {
          created_at: string;
          estado_anterior: Database["public"]["Enums"]["estado_tarea"] | null;
          estado_nuevo: Database["public"]["Enums"]["estado_tarea"];
          id: string;
          tarea_id: string;
          usuario_id: string | null;
        };
        Insert: {
          created_at?: string;
          estado_anterior?: Database["public"]["Enums"]["estado_tarea"] | null;
          estado_nuevo: Database["public"]["Enums"]["estado_tarea"];
          id?: string;
          tarea_id: string;
          usuario_id?: string | null;
        };
        Update: {
          created_at?: string;
          estado_anterior?: Database["public"]["Enums"]["estado_tarea"] | null;
          estado_nuevo?: Database["public"]["Enums"]["estado_tarea"];
          id?: string;
          tarea_id?: string;
          usuario_id?: string | null;
        };
        Relationships: [
          {
            foreignKeyName: "tareas_eventos_tarea_id_fkey";
            columns: ["tarea_id"];
            isOneToOne: false;
            referencedRelation: "tareas";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "tareas_eventos_usuario_id_fkey";
            columns: ["usuario_id"];
            isOneToOne: false;
            referencedRelation: "usuarios";
            referencedColumns: ["id"];
          },
        ];
      };
      tareas_hilos: {
        Row: {
          activo: boolean;
          creado_por: string;
          created_at: string;
          descripcion: string | null;
          estado: Database["public"]["Enums"]["estado_hilo"];
          id: string;
          posponer_desde: string | null;
          posponer_hasta: string | null;
          proyecto_id: string | null;
          responsable_id: string;
          titulo: string;
          updated_at: string;
          visibilidad: Database["public"]["Enums"]["visibilidad"];
        };
        Insert: {
          activo?: boolean;
          creado_por: string;
          created_at?: string;
          descripcion?: string | null;
          estado?: Database["public"]["Enums"]["estado_hilo"];
          id?: string;
          posponer_desde?: string | null;
          posponer_hasta?: string | null;
          proyecto_id?: string | null;
          responsable_id: string;
          titulo: string;
          updated_at?: string;
          visibilidad?: Database["public"]["Enums"]["visibilidad"];
        };
        Update: {
          activo?: boolean;
          creado_por?: string;
          created_at?: string;
          descripcion?: string | null;
          estado?: Database["public"]["Enums"]["estado_hilo"];
          id?: string;
          posponer_desde?: string | null;
          posponer_hasta?: string | null;
          proyecto_id?: string | null;
          responsable_id?: string;
          titulo?: string;
          updated_at?: string;
          visibilidad?: Database["public"]["Enums"]["visibilidad"];
        };
        Relationships: [
          {
            foreignKeyName: "tareas_hilos_creado_por_fkey";
            columns: ["creado_por"];
            isOneToOne: false;
            referencedRelation: "usuarios";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "tareas_hilos_proyecto_id_fkey";
            columns: ["proyecto_id"];
            isOneToOne: false;
            referencedRelation: "tareas_proyectos";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "tareas_hilos_responsable_id_fkey";
            columns: ["responsable_id"];
            isOneToOne: false;
            referencedRelation: "usuarios";
            referencedColumns: ["id"];
          },
        ];
      };
      tareas_hilos_notas: {
        Row: {
          activo: boolean;
          created_at: string;
          hilo_id: string;
          id: string;
          nota: string;
          usuario_id: string;
        };
        Insert: {
          activo?: boolean;
          created_at?: string;
          hilo_id: string;
          id?: string;
          nota: string;
          usuario_id: string;
        };
        Update: {
          activo?: boolean;
          created_at?: string;
          hilo_id?: string;
          id?: string;
          nota?: string;
          usuario_id?: string;
        };
        Relationships: [
          {
            foreignKeyName: "tareas_hilos_notas_hilo_id_fkey";
            columns: ["hilo_id"];
            isOneToOne: false;
            referencedRelation: "tareas_hilos";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "tareas_hilos_notas_usuario_id_fkey";
            columns: ["usuario_id"];
            isOneToOne: false;
            referencedRelation: "usuarios";
            referencedColumns: ["id"];
          },
        ];
      };
      tareas_notas: {
        Row: {
          activo: boolean;
          created_at: string;
          id: string;
          nota: string;
          tarea_id: string;
          usuario_id: string;
        };
        Insert: {
          activo?: boolean;
          created_at?: string;
          id?: string;
          nota: string;
          tarea_id: string;
          usuario_id: string;
        };
        Update: {
          activo?: boolean;
          created_at?: string;
          id?: string;
          nota?: string;
          tarea_id?: string;
          usuario_id?: string;
        };
        Relationships: [
          {
            foreignKeyName: "tareas_notas_tarea_id_fkey";
            columns: ["tarea_id"];
            isOneToOne: false;
            referencedRelation: "tareas";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "tareas_notas_usuario_id_fkey";
            columns: ["usuario_id"];
            isOneToOne: false;
            referencedRelation: "usuarios";
            referencedColumns: ["id"];
          },
        ];
      };
      tareas_plantillas: {
        Row: {
          activo: boolean;
          creado_por: string;
          created_at: string;
          descripcion: string | null;
          id: string;
          nombre: string;
          updated_at: string;
        };
        Insert: {
          activo?: boolean;
          creado_por: string;
          created_at?: string;
          descripcion?: string | null;
          id?: string;
          nombre: string;
          updated_at?: string;
        };
        Update: {
          activo?: boolean;
          creado_por?: string;
          created_at?: string;
          descripcion?: string | null;
          id?: string;
          nombre?: string;
          updated_at?: string;
        };
        Relationships: [
          {
            foreignKeyName: "tareas_plantillas_creado_por_fkey";
            columns: ["creado_por"];
            isOneToOne: false;
            referencedRelation: "usuarios";
            referencedColumns: ["id"];
          },
        ];
      };
      tareas_plantillas_items: {
        Row: {
          activo: boolean;
          created_at: string;
          id: string;
          orden: number;
          plantilla_id: string;
          titulo: string;
        };
        Insert: {
          activo?: boolean;
          created_at?: string;
          id?: string;
          orden?: number;
          plantilla_id: string;
          titulo: string;
        };
        Update: {
          activo?: boolean;
          created_at?: string;
          id?: string;
          orden?: number;
          plantilla_id?: string;
          titulo?: string;
        };
        Relationships: [
          {
            foreignKeyName: "tareas_plantillas_items_plantilla_id_fkey";
            columns: ["plantilla_id"];
            isOneToOne: false;
            referencedRelation: "tareas_plantillas";
            referencedColumns: ["id"];
          },
        ];
      };
      tareas_proyectos: {
        Row: {
          activo: boolean;
          creado_por: string;
          created_at: string;
          descripcion: string | null;
          id: string;
          nombre: string;
          updated_at: string;
          visibilidad: Database["public"]["Enums"]["visibilidad"];
        };
        Insert: {
          activo?: boolean;
          creado_por: string;
          created_at?: string;
          descripcion?: string | null;
          id?: string;
          nombre: string;
          updated_at?: string;
          visibilidad?: Database["public"]["Enums"]["visibilidad"];
        };
        Update: {
          activo?: boolean;
          creado_por?: string;
          created_at?: string;
          descripcion?: string | null;
          id?: string;
          nombre?: string;
          updated_at?: string;
          visibilidad?: Database["public"]["Enums"]["visibilidad"];
        };
        Relationships: [
          {
            foreignKeyName: "tareas_proyectos_creado_por_fkey";
            columns: ["creado_por"];
            isOneToOne: false;
            referencedRelation: "usuarios";
            referencedColumns: ["id"];
          },
        ];
      };
      tareas_proyectos_miembros: {
        Row: {
          activo: boolean;
          created_at: string;
          id: string;
          proyecto_id: string;
          usuario_id: string;
        };
        Insert: {
          activo?: boolean;
          created_at?: string;
          id?: string;
          proyecto_id: string;
          usuario_id: string;
        };
        Update: {
          activo?: boolean;
          created_at?: string;
          id?: string;
          proyecto_id?: string;
          usuario_id?: string;
        };
        Relationships: [
          {
            foreignKeyName: "tareas_proyectos_miembros_proyecto_id_fkey";
            columns: ["proyecto_id"];
            isOneToOne: false;
            referencedRelation: "tareas_proyectos";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "tareas_proyectos_miembros_usuario_id_fkey";
            columns: ["usuario_id"];
            isOneToOne: false;
            referencedRelation: "usuarios";
            referencedColumns: ["id"];
          },
        ];
      };
      usuario_notificaciones: {
        Row: {
          activo: boolean;
          actor_id: string | null;
          created_at: string;
          entidad: string;
          entidad_id: string;
          id: string;
          leida_at: string | null;
          tipo: Database["public"]["Enums"]["tipo_notificacion"];
          updated_at: string;
          usuario_id: string;
        };
        Insert: {
          activo?: boolean;
          actor_id?: string | null;
          created_at?: string;
          entidad: string;
          entidad_id: string;
          id?: string;
          leida_at?: string | null;
          tipo: Database["public"]["Enums"]["tipo_notificacion"];
          updated_at?: string;
          usuario_id: string;
        };
        Update: {
          activo?: boolean;
          actor_id?: string | null;
          created_at?: string;
          entidad?: string;
          entidad_id?: string;
          id?: string;
          leida_at?: string | null;
          tipo?: Database["public"]["Enums"]["tipo_notificacion"];
          updated_at?: string;
          usuario_id?: string;
        };
        Relationships: [
          {
            foreignKeyName: "usuario_notificaciones_actor_id_fkey";
            columns: ["actor_id"];
            isOneToOne: false;
            referencedRelation: "usuarios";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "usuario_notificaciones_usuario_id_fkey";
            columns: ["usuario_id"];
            isOneToOne: false;
            referencedRelation: "usuarios";
            referencedColumns: ["id"];
          },
        ];
      };
      usuario_submodulos: {
        Row: {
          activo: boolean;
          created_at: string;
          id: string;
          submodulo_id: string;
          updated_at: string;
          usuario_id: string;
        };
        Insert: {
          activo?: boolean;
          created_at?: string;
          id?: string;
          submodulo_id: string;
          updated_at?: string;
          usuario_id: string;
        };
        Update: {
          activo?: boolean;
          created_at?: string;
          id?: string;
          submodulo_id?: string;
          updated_at?: string;
          usuario_id?: string;
        };
        Relationships: [
          {
            foreignKeyName: "usuario_submodulos_submodulo_id_fkey";
            columns: ["submodulo_id"];
            isOneToOne: false;
            referencedRelation: "submodulos";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "usuario_submodulos_usuario_id_fkey";
            columns: ["usuario_id"];
            isOneToOne: false;
            referencedRelation: "usuarios";
            referencedColumns: ["id"];
          },
        ];
      };
      usuario_tutorial: {
        Row: {
          created_at: string;
          id: string;
          paso: string;
          updated_at: string;
          usuario_id: string;
        };
        Insert: {
          created_at?: string;
          id?: string;
          paso: string;
          updated_at?: string;
          usuario_id: string;
        };
        Update: {
          created_at?: string;
          id?: string;
          paso?: string;
          updated_at?: string;
          usuario_id?: string;
        };
        Relationships: [
          {
            foreignKeyName: "usuario_tutorial_usuario_id_fkey";
            columns: ["usuario_id"];
            isOneToOne: false;
            referencedRelation: "usuarios";
            referencedColumns: ["id"];
          },
        ];
      };
      usuario_widgets: {
        Row: {
          created_at: string;
          id: string;
          updated_at: string;
          usuario_id: string;
          visible: boolean;
          widget_id: string;
        };
        Insert: {
          created_at?: string;
          id?: string;
          updated_at?: string;
          usuario_id: string;
          visible?: boolean;
          widget_id: string;
        };
        Update: {
          created_at?: string;
          id?: string;
          updated_at?: string;
          usuario_id?: string;
          visible?: boolean;
          widget_id?: string;
        };
        Relationships: [
          {
            foreignKeyName: "usuario_widgets_usuario_id_fkey";
            columns: ["usuario_id"];
            isOneToOne: false;
            referencedRelation: "usuarios";
            referencedColumns: ["id"];
          },
        ];
      };
      usuarios: {
        Row: {
          activo: boolean;
          created_at: string;
          email: string;
          id: string;
          nombre: string;
          updated_at: string;
        };
        Insert: {
          activo?: boolean;
          created_at?: string;
          email: string;
          id: string;
          nombre: string;
          updated_at?: string;
        };
        Update: {
          activo?: boolean;
          created_at?: string;
          email?: string;
          id?: string;
          nombre?: string;
          updated_at?: string;
        };
        Relationships: [];
      };
    };
    Views: {
      [_ in never]: never;
    };
    Functions: {
      agregar_tareas_desde_plantilla: {
        Args: {
          p_asignados: string[];
          p_hilo_id: string;
          p_plantilla_id: string;
          p_responsable_id: string;
        };
        Returns: undefined;
      };
      convertir_tarea_en_hilo: {
        Args: { p_tarea_id: string };
        Returns: string;
      };
      crear_proyecto: {
        Args: {
          p_descripcion: string;
          p_miembros: string[];
          p_nombre: string;
          p_visibilidad: Database["public"]["Enums"]["visibilidad"];
        };
        Returns: string;
      };
      crear_tarea: {
        Args: {
          p_asignados: string[];
          p_descripcion: string;
          p_fecha_vencimiento: string;
          p_hilo_id: string;
          p_modo_completado: Database["public"]["Enums"]["modo_completado"];
          p_origen_app: string;
          p_origen_punto: string;
          p_paso_anterior_id: string;
          p_proyecto_id: string;
          p_recurrencia_cantidad: number;
          p_recurrencia_unidad: Database["public"]["Enums"]["recurrencia_unidad"];
          p_responsable_id: string;
          p_temperatura: number;
          p_titulo: string;
          p_visibilidad: Database["public"]["Enums"]["visibilidad"];
        };
        Returns: string;
      };
      desactivar_hilo: { Args: { p_hilo_id: string }; Returns: undefined };
      deshacer_conversion_hilo: {
        Args: { p_hilo_id: string };
        Returns: undefined;
      };
      editar_proyecto: {
        Args: {
          p_descripcion: string;
          p_id: string;
          p_miembros: string[];
          p_nombre: string;
          p_visibilidad: Database["public"]["Enums"]["visibilidad"];
        };
        Returns: undefined;
      };
      editar_tarea: {
        Args: {
          p_asignados: string[];
          p_descripcion: string;
          p_fecha_vencimiento: string;
          p_id: string;
          p_proyecto_id: string;
          p_recurrencia_cantidad: number;
          p_recurrencia_unidad: Database["public"]["Enums"]["recurrencia_unidad"];
          p_responsable_id: string;
          p_temperatura: number;
          p_titulo: string;
          p_visibilidad: Database["public"]["Enums"]["visibilidad"];
        };
        Returns: undefined;
      };
      es_asignado_tarea: { Args: { p_tarea_id: string }; Returns: boolean };
      es_creador_proyecto: {
        Args: { p_proyecto_id: string };
        Returns: boolean;
      };
      es_miembro_proyecto: {
        Args: { p_proyecto_id: string; p_usuario_id: string };
        Returns: boolean;
      };
      es_miembro_proyecto_de_tarea: {
        Args: { p_tarea_id: string; p_usuario_id: string };
        Returns: boolean;
      };
      es_responsable_tarea: { Args: { p_tarea_id: string }; Returns: boolean };
      notificaciones_avisos: {
        Args: never;
        Returns: {
          vencen_hoy: number;
          vencidas: number;
        }[];
      };
      notificaciones_listar: {
        Args: { p_limite?: number };
        Returns: {
          actor: string;
          created_at: string;
          destino: string;
          destino_id: string;
          etiqueta: string;
          id: string;
          leida: boolean;
          motivo: string;
          tipo: Database["public"]["Enums"]["tipo_notificacion"];
        }[];
      };
      notificar: {
        Args: {
          p_actor_id: string;
          p_entidad: string;
          p_entidad_id: string;
          p_tipo: Database["public"]["Enums"]["tipo_notificacion"];
          p_usuario_id: string;
        };
        Returns: undefined;
      };
      obras_array_sin_duplicados: { Args: { a: unknown }; Returns: boolean };
      obras_auditoria_accesos: {
        Args: { p_dias?: number };
        Returns: {
          acceso_id: string;
          contexto: string;
          created_at: string;
          persona: string;
          persona_id: string;
          usuario: string;
          usuario_id: string;
        }[];
      };
      obras_auditoria_transferencias: {
        Args: { p_dias?: number };
        Returns: {
          a_usuario: string;
          created_at: string;
          de_usuario: string;
          ejecutada_por: string;
          obra: string;
          obra_id: string;
          transferencia_id: string;
        }[];
      };
      obras_buscar: {
        Args: { p_texto: string };
        Returns: {
          duenio: string;
          es_ajeno: boolean;
          id: string;
          subtitulo: string;
          tipo: string;
          titulo: string;
        }[];
      };
      obras_buscar_duplicados_empresa: {
        Args: {
          p_excluir_id?: string;
          p_nombre_comercial?: string;
          p_razon_social: string;
        };
        Returns: {
          cargada_por: string;
          empresa_id: string;
          es_mia: boolean;
          localidad: string;
          nombre_comercial: string;
          razon_social: string;
        }[];
      };
      obras_buscar_duplicados_obra: {
        Args: {
          p_direccion?: string;
          p_excluir_id?: string;
          p_localidad?: string;
          p_nombre: string;
        };
        Returns: {
          direccion: string;
          es_mia: boolean;
          localidad: string;
          nombre: string;
          obra_id: string;
          responsable: string;
        }[];
      };
      obras_buscar_duplicados_persona: {
        Args: {
          p_apellido?: string;
          p_email?: string;
          p_excluir_id?: string;
          p_nombre: string;
          p_telefono?: string;
        };
        Returns: {
          apellido: string;
          coincide: string;
          empresa: string;
          nombre: string;
          persona_id: string;
        }[];
      };
      obras_buscar_empresas: {
        Args: { p_texto: string };
        Returns: {
          duenio: string;
          es_ajeno: boolean;
          id: string;
          subtitulo: string;
          tipo: string;
          titulo: string;
        }[];
      };
      obras_buscar_obras: {
        Args: { p_texto: string };
        Returns: {
          duenio: string;
          es_ajeno: boolean;
          id: string;
          subtitulo: string;
          tipo: string;
          titulo: string;
        }[];
      };
      obras_buscar_personas: {
        Args: { p_texto: string };
        Returns: {
          duenio: string;
          es_ajeno: boolean;
          id: string;
          subtitulo: string;
          tipo: string;
          titulo: string;
        }[];
      };
      obras_compartidos_por_mi: {
        Args: never;
        Returns: {
          compartida_el: string;
          entidad_id: string;
          entidad_nombre: string;
          origen_id: string | null;
          origen_nombre: string | null;
          origen_tipo: string | null;
          tipo: string;
          usuario_id: string;
          usuario_nombre: string;
        }[];
      };
      obras_compartir_empresa: {
        Args: {
          p_empresa_id: string;
          p_personas?: string[];
          p_usuario_id: string;
        };
        Returns: undefined;
      };
      obras_compartir_obra: {
        Args: {
          p_empresas?: string[];
          p_obra_id: string;
          p_personas?: string[];
          p_usuario_id: string;
        };
        Returns: undefined;
      };
      obras_compartir_persona: {
        Args: { p_persona_id: string; p_usuario_id: string };
        Returns: undefined;
      };
      obras_contactos_exclusivos_de_empresa: {
        Args: { p_empresa_id: string };
        Returns: {
          detalle: string;
          etiqueta: string;
          id: string;
          tipo: string;
        }[];
      };
      obras_contactos_exclusivos_de_obra: {
        Args: { p_obra_id: string };
        Returns: {
          detalle: string;
          etiqueta: string;
          id: string;
          tipo: string;
        }[];
      };
      obras_es_mi_obra: { Args: { p_obra_id: string }; Returns: boolean };
      obras_etiqueta: {
        Args: { p_id: string; p_tipo: string };
        Returns: string;
      };
      obras_ficha_persona: {
        Args: { p_ctx_id?: string; p_ctx_tipo?: string; p_persona_id: string };
        Returns: {
          apellido: string;
          creado_por: string;
          created_at: string;
          email: string;
          id: string;
          nombre: string;
          observaciones: string;
          telefono: string;
          updated_at: string;
          whatsapp: string;
        }[];
      };
      obras_guardar_referente: {
        Args: {
          p_obra_id: string;
          p_observaciones?: string;
          p_persona_id: string;
          p_porcentaje_comision: number;
        };
        Returns: string;
      };
      obras_historial_aprobaciones: {
        Args: { p_dias?: number };
        Returns: {
          aprobacion_id: string;
          aprobada: boolean;
          created_at: string;
          decidido_por: string;
          etiqueta: string;
          motivo: string;
          tipo: string;
        }[];
      };
      obras_normalizar: { Args: { t: string }; Returns: string };
      obras_normalizar_telefono: { Args: { t: string }; Returns: string };
      obras_pendiente_similares: {
        Args: { p_id: string; p_tipo: string };
        Returns: {
          detalle: string;
          etiqueta: string;
        }[];
      };
      obras_pendientes: {
        Args: never;
        Returns: {
          created_at: string;
          etiqueta: string;
          motivo: string;
          registro_id: string;
          solicitante: string;
          tipo: string;
        }[];
      };
      obras_persona_grant_ctx_vigente: {
        Args: { p_persona_id: string };
        Returns: boolean;
      };
      obras_personas_de_empresa: {
        Args: { p_empresa_id: string; p_obra_id?: string };
        Returns: {
          apellido: string;
          cargo: string;
          es_mia: boolean;
          es_principal: boolean;
          nombre: string;
          persona_id: string;
          ya_en_obra: boolean;
        }[];
      };
      obras_puede_ver_empresa: {
        Args: { p_empresa_id: string };
        Returns: boolean;
      };
      obras_puede_ver_obra: { Args: { p_obra_id: string }; Returns: boolean };
      obras_puede_ver_persona: {
        Args: { p_persona_id: string };
        Returns: boolean;
      };
      obras_relaciones_compartibles_empresa: {
        Args: { p_empresa_id: string; p_usuario_id: string };
        Returns: {
          detalle: string;
          etiqueta: string;
          id: string;
          tipo: string;
          ya_compartida: boolean;
        }[];
      };
      obras_relaciones_compartibles_obra: {
        Args: { p_obra_id: string; p_usuario_id: string };
        Returns: {
          detalle: string;
          etiqueta: string;
          id: string;
          tipo: string;
          ya_compartida: boolean;
        }[];
      };
      obras_resolver_pendiente: {
        Args: {
          p_aprobar: boolean;
          p_id: string;
          p_motivo?: string;
          p_tipo: string;
        };
        Returns: undefined;
      };
      obras_revocar_empresa: {
        Args: { p_empresa_id: string; p_usuario_id: string };
        Returns: undefined;
      };
      obras_revocar_obra: {
        Args: { p_obra_id: string; p_usuario_id: string };
        Returns: undefined;
      };
      obras_revocar_persona: {
        Args: { p_persona_id: string; p_usuario_id: string };
        Returns: undefined;
      };
      obras_set_activo: {
        Args: { p_activo: boolean; p_obra_id: string };
        Returns: undefined;
      };
      obras_similares_empresa: {
        Args: {
          p_excluir_id?: string;
          p_nombre_comercial?: string;
          p_razon_social: string;
        };
        Returns: {
          empresa_id: string;
          score: number;
        }[];
      };
      obras_similares_obra: {
        Args: {
          p_direccion?: string;
          p_excluir_id?: string;
          p_localidad?: string;
          p_nombre: string;
        };
        Returns: {
          misma_localidad: boolean;
          obra_id: string;
          score: number;
        }[];
      };
      obras_similares_persona: {
        Args: {
          p_apellido?: string;
          p_email?: string;
          p_excluir_id?: string;
          p_nombre: string;
          p_telefono?: string;
        };
        Returns: {
          coincide: string;
          persona_id: string;
        }[];
      };
      obras_solicitante: {
        Args: { p_id: string; p_tipo: string };
        Returns: string;
      };
      obras_transferir: {
        Args: {
          p_a_usuario_id: string;
          p_contactos_exclusivos?: string[];
          p_obra_id: string;
        };
        Returns: undefined;
      };
      obras_transferir_empresa: {
        Args: {
          p_a_usuario_id: string;
          p_empresa_id: string;
          p_personas_exclusivas?: string[];
        };
        Returns: undefined;
      };
      obras_transferir_persona: {
        Args: { p_a_usuario_id: string; p_persona_id: string };
        Returns: undefined;
      };
      obras_vincular_empresa: {
        Args: {
          p_empresa_id: string;
          p_obra_id: string;
          p_observaciones?: string;
          p_personas?: Json;
          p_roles: Database["public"]["Enums"]["rol_empresa"][];
        };
        Returns: {
          personas_agregadas: number;
          personas_pendientes: number;
          vinculo_id: string;
          vinculo_pendiente: boolean;
        }[];
      };
      proyecto_tiene_miembros: {
        Args: { p_proyecto_id: string };
        Returns: boolean;
      };
      puede_ver_hilo: { Args: { p_hilo_id: string }; Returns: boolean };
      reactivar_posponer_vencidos: { Args: never; Returns: undefined };
      reasignar_tarea: {
        Args: {
          p_asignados: string[];
          p_responsable_id: string;
          p_tarea_id: string;
        };
        Returns: undefined;
      };
      sincronizar_asignados: {
        Args: { p_asignados: string[]; p_tarea_id: string };
        Returns: undefined;
      };
      tiene_permiso: { Args: { p_codigo: string }; Returns: boolean };
    };
    Enums: {
      estado_hilo: "abierto" | "cerrado";
      estado_obra:
        | "idea"
        | "en_cotizacion"
        | "en_ejecucion"
        | "en_postventa"
        | "perdida"
        | "terminada";
      estado_tarea: "pendiente" | "en_progreso" | "completada" | "cancelada";
      modo_completado: "manual" | "automatico" | "hibrido";
      motivo_perdida:
        | "perdimos_licitacion"
        | "eligieron_otro_proveedor"
        | "precio"
        | "especificacion_fuera_de_provision"
        | "obra_cancelada"
        | "sin_interes"
        | "otro";
      origen_obra:
        | "arquitecto"
        | "inmobiliaria"
        | "constructora"
        | "desarrolladora"
        | "referido"
        | "deteccion_propia"
        | "internet"
        | "otro";
      provincia:
        | "caba"
        | "buenos_aires"
        | "catamarca"
        | "chaco"
        | "chubut"
        | "cordoba"
        | "corrientes"
        | "entre_rios"
        | "formosa"
        | "jujuy"
        | "la_pampa"
        | "la_rioja"
        | "mendoza"
        | "misiones"
        | "neuquen"
        | "rio_negro"
        | "salta"
        | "san_juan"
        | "san_luis"
        | "santa_cruz"
        | "santa_fe"
        | "santiago_del_estero"
        | "tierra_del_fuego"
        | "tucuman";
      recurrencia_unidad: "dia" | "mes";
      rol_empresa:
        | "constructora"
        | "desarrolladora"
        | "inmobiliaria"
        | "estudio_arquitectura"
        | "direccion_obra"
        | "otro";
      rol_persona:
        | "arquitecto"
        | "desarrollador"
        | "inversor"
        | "director_obra"
        | "compras"
        | "oficina_tecnica"
        | "decisor"
        | "influenciador"
        | "contacto_comercial"
        | "otro";
      tipo_notificacion:
        | "alta_aprobada"
        | "alta_rechazada"
        | "obra_transferida"
        | "tarea_asignada";
      tipo_obra:
        | "edificio"
        | "casa"
        | "refaccion"
        | "complejo_viviendas"
        | "local"
        | "oficina"
        | "hotel"
        | "otro";
      tipo_submodulo: "vista" | "funcion";
      visibilidad: "publico" | "privado";
    };
    CompositeTypes: {
      [_ in never]: never;
    };
  };
};

type DatabaseWithoutInternals = Omit<Database, "__InternalSupabase">;

type DefaultSchema = DatabaseWithoutInternals[Extract<
  keyof Database,
  "public"
>];

export type Tables<
  DefaultSchemaTableNameOrOptions extends
    | keyof (DefaultSchema["Tables"] & DefaultSchema["Views"])
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends (DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals;
  }
    ? keyof (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
        DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])
    : never) = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals;
}
  ? (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
      DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])[TableName] extends {
      Row: infer R;
    }
    ? R
    : never
  : DefaultSchemaTableNameOrOptions extends keyof (DefaultSchema["Tables"] &
        DefaultSchema["Views"])
    ? (DefaultSchema["Tables"] &
        DefaultSchema["Views"])[DefaultSchemaTableNameOrOptions] extends {
        Row: infer R;
      }
      ? R
      : never
    : never;

export type TablesInsert<
  DefaultSchemaTableNameOrOptions extends
    keyof DefaultSchema["Tables"] | { schema: keyof DatabaseWithoutInternals },
  TableName extends (DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals;
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never) = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals;
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Insert: infer I;
    }
    ? I
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Insert: infer I;
      }
      ? I
      : never
    : never;

export type TablesUpdate<
  DefaultSchemaTableNameOrOptions extends
    keyof DefaultSchema["Tables"] | { schema: keyof DatabaseWithoutInternals },
  TableName extends (DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals;
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never) = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals;
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Update: infer U;
    }
    ? U
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Update: infer U;
      }
      ? U
      : never
    : never;

export type Enums<
  DefaultSchemaEnumNameOrOptions extends
    keyof DefaultSchema["Enums"] | { schema: keyof DatabaseWithoutInternals },
  EnumName extends (DefaultSchemaEnumNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals;
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"]
    : never) = never,
> = DefaultSchemaEnumNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals;
}
  ? DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"][EnumName]
  : DefaultSchemaEnumNameOrOptions extends keyof DefaultSchema["Enums"]
    ? DefaultSchema["Enums"][DefaultSchemaEnumNameOrOptions]
    : never;

export type CompositeTypes<
  PublicCompositeTypeNameOrOptions extends
    | keyof DefaultSchema["CompositeTypes"]
    | { schema: keyof DatabaseWithoutInternals },
  CompositeTypeName extends (PublicCompositeTypeNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals;
  }
    ? keyof DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"]
    : never) = never,
> = PublicCompositeTypeNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals;
}
  ? DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"][CompositeTypeName]
  : PublicCompositeTypeNameOrOptions extends keyof DefaultSchema["CompositeTypes"]
    ? DefaultSchema["CompositeTypes"][PublicCompositeTypeNameOrOptions]
    : never;

export const Constants = {
  public: {
    Enums: {
      estado_hilo: ["abierto", "cerrado"],
      estado_obra: [
        "idea",
        "en_cotizacion",
        "en_ejecucion",
        "en_postventa",
        "perdida",
        "terminada",
      ],
      estado_tarea: ["pendiente", "en_progreso", "completada", "cancelada"],
      modo_completado: ["manual", "automatico", "hibrido"],
      motivo_perdida: [
        "perdimos_licitacion",
        "eligieron_otro_proveedor",
        "precio",
        "especificacion_fuera_de_provision",
        "obra_cancelada",
        "sin_interes",
        "otro",
      ],
      origen_obra: [
        "arquitecto",
        "inmobiliaria",
        "constructora",
        "desarrolladora",
        "referido",
        "deteccion_propia",
        "internet",
        "otro",
      ],
      provincia: [
        "caba",
        "buenos_aires",
        "catamarca",
        "chaco",
        "chubut",
        "cordoba",
        "corrientes",
        "entre_rios",
        "formosa",
        "jujuy",
        "la_pampa",
        "la_rioja",
        "mendoza",
        "misiones",
        "neuquen",
        "rio_negro",
        "salta",
        "san_juan",
        "san_luis",
        "santa_cruz",
        "santa_fe",
        "santiago_del_estero",
        "tierra_del_fuego",
        "tucuman",
      ],
      recurrencia_unidad: ["dia", "mes"],
      rol_empresa: [
        "constructora",
        "desarrolladora",
        "inmobiliaria",
        "estudio_arquitectura",
        "direccion_obra",
        "otro",
      ],
      rol_persona: [
        "arquitecto",
        "desarrollador",
        "inversor",
        "director_obra",
        "compras",
        "oficina_tecnica",
        "decisor",
        "influenciador",
        "contacto_comercial",
        "otro",
      ],
      tipo_notificacion: [
        "alta_aprobada",
        "alta_rechazada",
        "obra_transferida",
        "tarea_asignada",
      ],
      tipo_obra: [
        "edificio",
        "casa",
        "refaccion",
        "complejo_viviendas",
        "local",
        "oficina",
        "hotel",
        "otro",
      ],
      tipo_submodulo: ["vista", "funcion"],
      visibilidad: ["publico", "privado"],
    },
  },
} as const;
