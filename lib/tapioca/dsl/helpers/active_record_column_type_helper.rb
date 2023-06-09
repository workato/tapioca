# typed: strict
# frozen_string_literal: true

module Tapioca
  module Dsl
    module Helpers
      class ActiveRecordColumnTypeHelper
        extend T::Sig
        include RBIHelper

        sig { params(constant: T.class_of(ActiveRecord::Base)).void }
        def initialize(constant)
          @constant = constant
        end

        sig { params(column_name: String).returns([RBI::Type, RBI::Type]) }
        def type_for(column_name)
          return [RBI::Type.untyped, RBI::Type.untyped] if do_not_generate_strong_types?(@constant)

          column = @constant.columns_hash[column_name]
          column_type = @constant.attribute_types[column_name]
          getter_type = type_for_activerecord_value(column_type)
          setter_type =
            case column_type
            when ActiveRecord::Enum::EnumType
              enum_setter_type(column_type)
            else
              getter_type
            end

          if column&.null
            getter_type = getter_type.nilable unless not_nilable_serialized_column?(column_type)
            return [getter_type, setter_type.nilable]
          end

          if column_name == @constant.primary_key ||
              column_name == "created_at" ||
              column_name == "updated_at"
            getter_type = getter_type.nilable
          end

          [getter_type, setter_type]
        end

        private

        sig { params(column_type: T.untyped).returns(RBI::Type) }
        def type_for_activerecord_value(column_type)
          case column_type
          when defined?(MoneyColumn) && MoneyColumn::ActiveRecordType
            RBI::Type.simple("::Money")
          when ActiveRecord::Type::Integer
            RBI::Type.simple("::Integer")
          when ActiveRecord::Type::String
            RBI::Type.simple("::String")
          when ActiveRecord::Type::Date
            RBI::Type.simple("::Date")
          when ActiveRecord::Type::Decimal
            RBI::Type.simple("::BigDecimal")
          when ActiveRecord::Type::Float
            RBI::Type.simple("::Float")
          when ActiveRecord::Type::Boolean
            RBI::Type.boolean
          when ActiveRecord::Type::DateTime, ActiveRecord::Type::Time
            RBI::Type.simple("::Time")
          when ActiveRecord::AttributeMethods::TimeZoneConversion::TimeZoneConverter
            RBI::Type.simple("::ActiveSupport::TimeWithZone")
          when ActiveRecord::Enum::EnumType
            RBI::Type.simple("::String")
          when ActiveRecord::Type::Serialized
            serialized_column_type(column_type)
          when defined?(ActiveRecord::ConnectionAdapters::PostgreSQL::OID::Hstore) &&
            ActiveRecord::ConnectionAdapters::PostgreSQL::OID::Hstore
            RBI::Type.generic("T::Hash", RBI::Type.simple("::String"), RBI::Type.simple("::String"))
          when defined?(ActiveRecord::ConnectionAdapters::PostgreSQL::OID::Array) &&
            ActiveRecord::ConnectionAdapters::PostgreSQL::OID::Array
            RBI::Type.generic("T::Array", type_for_activerecord_value(column_type.subtype))
          else
            handle_unknown_type(column_type)
          end
        end

        sig { params(constant: Module).returns(T::Boolean) }
        def do_not_generate_strong_types?(constant)
          Object.const_defined?(:StrongTypeGeneration) &&
            !(constant.singleton_class < Object.const_get(:StrongTypeGeneration))
        end

        sig { params(column_type: BasicObject).returns(RBI::Type) }
        def handle_unknown_type(column_type)
          return RBI::Type.untyped unless ActiveModel::Type::Value === column_type
          return RBI::Type.untyped if Runtime::GenericTypeRegistry.generic_type_instance?(column_type)

          lookup_return_type_of_method(column_type, :deserialize) ||
            lookup_return_type_of_method(column_type, :cast) ||
            lookup_arg_type_of_method(column_type, :serialize) ||
            RBI::Type.untyped
        end

        sig { params(column_type: ActiveModel::Type::Value, method: Symbol).returns(T.nilable(RBI::Type)) }
        def lookup_return_type_of_method(column_type, method)
          signature = Runtime::Reflection.signature_of(column_type.method(method))
          return unless signature

          return_type = signature.return_type
          return if return_type == T::Private::Types::Void || return_type == T::Private::Types::NotTyped

          RBI::Type.verbatim(return_type.to_s)
        end

        sig { params(column_type: ActiveModel::Type::Value, method: Symbol).returns(T.nilable(RBI::Type)) }
        def lookup_arg_type_of_method(column_type, method)
          signature = Runtime::Reflection.signature_of(column_type.method(method))
          return unless signature

          # Arg types is an array [name, type] entries, so we desctructure the type of
          # first argument to get the first argument type
          _, first_argument_type = signature.arg_types.first

          RBI::Type.verbatim(first_argument_type.to_s)
        end

        sig { params(column_type: ActiveRecord::Enum::EnumType).returns(RBI::Type) }
        def enum_setter_type(column_type)
          # In Rails < 7 this method is private. When support for that is dropped we can call the method directly
          case column_type.send(:subtype)
          when ActiveRecord::Type::Integer
            RBI::Type.any(RBI::Type.simple("::String"), RBI::Type.simple("::Symbol"), RBI::Type.simple("::Integer"))
          else
            RBI::Type.any(RBI::Type.simple("::String"), RBI::Type.simple("::Symbol"))
          end
        end

        sig { params(column_type: ActiveRecord::Type::Serialized).returns(RBI::Type) }
        def serialized_column_type(column_type)
          case column_type.coder
          when ActiveRecord::Coders::YAMLColumn
            case column_type.coder.object_class
            when Array.singleton_class
              RBI::Type.generic("T::Array", RBI::Type.untyped)
            when Hash.singleton_class
              RBI::Type.generic("T::Hash", RBI::Type.untyped, RBI::Type.untyped)
            else
              RBI::Type.untyped
            end
          else
            RBI::Type.untyped
          end
        end

        sig { params(column_type: T.untyped).returns(T::Boolean) }
        def not_nilable_serialized_column?(column_type)
          return false unless column_type.is_a?(ActiveRecord::Type::Serialized)
          return false unless column_type.coder.is_a?(ActiveRecord::Coders::YAMLColumn)

          [Array.singleton_class, Hash.singleton_class].include?(column_type.coder.object_class.singleton_class)
        end
      end
    end
  end
end
