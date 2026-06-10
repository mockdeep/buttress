RSpec.describe Buttress::Writer do
  let(:base) { File.expand_path('../../tmp/writer_spec', __dir__) }

  around do |example|
    FileUtils.rm_rf(base)
    FileUtils.mkdir_p(base)
    example.run
    FileUtils.rm_rf(base)
  end

  def create_project(name)
    root = File.join(base, name)
    FileUtils.mkdir_p(root)
    File.write(File.join(root, 'Gemfile'), '')
    root
  end

  def create_file(root, relative)
    path = File.join(root, relative)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, '')
    path
  end

  it 'mirrors app/ paths into spec/' do
    root = create_project('railsy')
    file = create_file(root, 'app/models/user.rb')

    spec_path = described_class.call(file, "generated\n")

    expect(spec_path).to eq(File.join(root, 'spec/models/user_spec.rb'))
    expect(File.read(spec_path)).to eq("generated\n")
  end

  it 'mirrors lib/ paths into spec/' do
    root = create_project('gemmy')
    file = create_file(root, 'lib/gemmy/thing.rb')

    spec_path = described_class.call(file, "generated\n")

    expect(spec_path).to eq(File.join(root, 'spec/gemmy/thing_spec.rb'))
  end

  it 'keeps other path prefixes when mirroring' do
    root = create_project('plain')
    file = create_file(root, 'models/user.rb')

    spec_path = described_class.call(file, "generated\n")

    expect(spec_path).to eq(File.join(root, 'spec/models/user_spec.rb'))
  end

  it 'refuses to overwrite an existing spec' do
    root = create_project('careful')
    file = create_file(root, 'app/models/user.rb')
    create_file(root, 'spec/models/user_spec.rb')

    expect { described_class.call(file, "generated\n") }
      .to raise_error(Buttress::Error, /refusing to overwrite/)
  end
end
