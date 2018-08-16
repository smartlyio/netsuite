# https://system.eu1.netsuite.com/app/help/helpcenter.nl?fid=section_N3481360.html
module NetSuite
  module Actions
    class AddList
      include Support::Requests

      def initialize(*objects)
        @objects = objects
      end

      private

      def request(credentials={})
        NetSuite::Configuration.connection(
          { element_form_default: :unqualified }, credentials
        ).call(:add_list, message: request_body)
      end

      # <soap:Body>
      #   <addList>
      #     <record xsi:type="listRel:Customer" externalId="ext1">
      #       <listRel:entityId>Shutter Fly</listRel:entityId>
      #       <listRel:companyName>Shutter Fly, Inc</listRel:companyName>
      #     </record>
      #     <record xsi:type="listRel:Customer" externalId="ext2">
      #       <listRel:entityId>Target</listRel:entityId>
      #       <listRel:companyName>Target</listRel:companyName>
      #     </record>
      #   </addList>
      # </soap:Body>
      def request_body
        attrs = @objects.map do |o|
          hash = o.to_record.merge({
            '@xsi:type' => o.record_type
          })

          if o.respond_to?(:external_id) && o.external_id
            hash['@externalId'] = o.external_id
          end

          hash
        end

        { 'record' => attrs }
      end

      def response_hash
        @response_hash ||= Array[@response.body[:add_list_response][:write_response_list][:write_response]].flatten
      end

      def response_body
        @response_body ||= response_hash.map { |h| h[:base_ref] }
      end

      def response_errors
        if response_hash.any? { |h| h[:status] && h[:status][:status_detail] }
          @response_errors ||= errors
        end
      end

      def errors
        errors = response_hash.select { |h| h[:status] }.each_with_index.map do |obj, index|
          error_obj = obj[:status][:status_detail]
          next if error_obj.nil?
          error_obj = [error_obj] if error_obj.class == Hash
          errors = error_obj.map do |error|
            NetSuite::Error.new(error)
          end

          external_id =
            (obj[:base_ref] && obj[:base_ref][:@external_id]) ||
            (@objects[index].respond_to?(:external_id) && @objects[index].external_id)
          [external_id, errors]
        end
        Hash[errors]
      end

      def success?
        @success ||= response_hash.all? { |h| h[:status][:@is_success] == 'true' }
      end

      module Support

        def self.included(base)
          base.extend(ClassMethods)
        end

        module ClassMethods
          def add_list(records, credentials = {})
            netsuite_records = records.map do |r|
              if r.is_a?(self)
                r
              else
                new(r)
              end
            end

            response = NetSuite::Actions::AddList.call(netsuite_records, credentials)

            if response.success?
              response.body.map do |attr|
                record = netsuite_records.find do |r|
                  r.external_id == attr[:@external_id]
                end

                record.instance_variable_set('@internal_id', attr[:@internal_id])
              end

              netsuite_records
            else
              false
            end
          end
        end
      end
    end
  end
end
