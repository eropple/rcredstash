module CredStash::Repository
  class DynamoDB
    def initialize(client: nil)
      @client = client || Aws::DynamoDB::Client.new
    end

    def get(name)
      select(name, limit: 1).first.tap do |item|
        unless item
          raise CredStash::ItemNotFound, "#{name} is not found"
        end
      end
    end

    def select(name, pluck: nil, limit: nil)
      params = {
        table_name: CredStash.config.table_name,
        consistent_read: true,
        key_condition_expression: "#name = :name",
        expression_attribute_names: { "#name" => "name"},
        expression_attribute_values: { ":name" => name }
      }

      if pluck
        params[:projection_expression] = pluck
      end

      if limit
        params[:limit] = limit
        params[:scan_index_forward] = false
      end

      @client.query(params).items.map do |item|
        Item.new(
          key: item["key"],
          contents: item["contents"],
          name: item["name"],
          version: item["version"]
        )
      end
    end

    def put(item)
      @client.put_item(
        table_name: CredStash.config.table_name,
        item: {
          name: item.name,
          version: item.version,
          key: item.key,
          contents: item.contents,
          hmac: item.hmac
        },
        condition_expression: "attribute_not_exists(#name)",
        expression_attribute_names: { "#name" => "name" },
      )
    end

    def list
      @client.scan(
        table_name: CredStash.config.table_name,
        projection_expression: '#name, version',
        expression_attribute_names: { "#name" => "name" },
      ).items.map do |item|
        Item.new(name: item['name'], version: item['version'])
      end
    end

    def delete(item)
      @client.delete_item(
        table_name: CredStash.config.table_name,
        key: {
          name: item.name,
          version: item.version
        }
      )
    end

    def setup
      @client.create_table(
        table_name: CredStash.config.table_name,
        key_schema: [
          { attribute_name: 'name', key_type: 'HASH' },
          { attribute_name: 'version', key_type: 'RANGE' },
        ],
        attribute_definitions: [
          { attribute_name: 'name', attribute_type: 'S' },
          { attribute_name: 'version', attribute_type: 'S' },
        ],
        provisioned_throughput: {
          read_capacity_units: 1,
          write_capacity_units: 1,
        },
      )
    end
  end
end
