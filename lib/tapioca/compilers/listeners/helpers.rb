# typed: strict
# frozen_string_literal: true

require "pathname"

module Tapioca
  module Compilers
    module NodeListeners
      class Helpers < Base
        extend T::Sig

        include Reflection

        private

        sig { override.params(event: Tapioca::Compilers::SymbolTableCompiler::ScopeEvent).void }
        def on_scope(event)
          constant = event.constant

          abstract_type = T::Private::Abstract::Data.get(constant, :abstract_type) ||
          T::Private::Abstract::Data.get(singleton_class_of(constant), :abstract_type)

          event.scope << RBI::Helper.new(abstract_type.to_s) if abstract_type
          event.scope << RBI::Helper.new("final") if T::Private::Final.final_module?(constant)
          event.scope << RBI::Helper.new("sealed") if T::Private::Sealed.sealed_module?(constant)
        end
      end
    end
  end
end
