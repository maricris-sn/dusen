# encoding: utf-8

require 'spec_helper'

shared_examples_for 'model with search syntax' do

  describe '.search' do

    it 'should find records by given words' do
      match = subject.create!(:name => 'Abraham')
      no_match = subject.create!(:name => 'Elizabath')
      subject.search('Abraham').to_a.should == [match]
    end

    it 'should not find stale text after fields were updated (bugfix)' do
      match = subject.create!(:name => 'Abraham')
      no_match = subject.create!(:name => 'Elizabath')
      match.update_attributes!(:name => 'Johnny')
      subject.search('Abraham').to_a.should be_empty
      subject.search('Johnny').to_a.should == [match]
    end

    it 'should AND multiple words' do
      match = subject.create!(:name => 'Abraham Lincoln')
      no_match = subject.create!(:name => 'Abraham')
      subject.search('Abraham Lincoln').to_a.should == [match]
    end

    it 'should find records by phrases' do
      match = subject.create!(:name => 'Abraham Lincoln')
      no_match = subject.create!(:name => 'Abraham John Lincoln')
      subject.search('"Abraham Lincoln"').to_a.should == [match]
    end

    it 'should find records by qualified fields' do
      match = subject.create!(:name => 'foo@bar.com', :email => 'foo@bar.com')
      no_match = subject.create!(:name => 'foo@bar.com', :email => 'bam@baz.com')
      subject.search('email:foo@bar.com').to_a.should == [match]
    end

    it 'should find no records if a nonexistent qualifier is used' do
      subject.create!(:name => 'someuser', :email => 'foo@bar.com')
      subject.search('nonexistent_qualifier:someuser email:foo@bar.com').to_a.should == []
    end

    it 'should allow phrases as values for qualified field queries' do
      match = subject.create!(:name => 'Foo Bar', :city => 'Foo Bar')
      no_match = subject.create!(:name => 'Foo Bar', :city => 'Bar Foo')
      subject.search('city:"Foo Bar"').to_a.should == [match]
    end

    it 'should allow to mix multiple types of tokens in a single query' do
      match = subject.create!(:name => 'Abraham', :city => 'Foohausen')
      no_match = subject.create!(:name => 'Abraham', :city => 'Barhausen')
      subject.search('Foo city:Foohausen').to_a.should == [match]
    end

    it 'should not find records from another model' do
      match = subject.create!(:name => 'Abraham')
      Recipe.create!(:name => 'Abraham')
      subject.search('Abraham').to_a.should == [match]
    end

    it 'should find words where one letter is separated from other letters by a period' do
      match = subject.create!(:name => 'E.ONNNEN')
      subject.search('E.ONNNEN').to_a.should == [match]
    end

    it 'should find words where one letter is separated from other letters by a period' do
      match = subject.create!(:name => 'E;ONNNEN')
      subject.search('E;ONNNEN')
      subject.search('E;ONNNEN').to_a.should == [match]
    end

    it 'should distinguish between "Baden" and "Baden-Baden" (bugfix)' do
      match = subject.create!(:city => 'Baden-Baden')
      no_match = subject.create!(:city => 'Baden')
      subject.search('Baden-Baden').to_a.should == [match]
    end

    context 'when the given query is blank' do

      it 'returns all records' do
        match = subject.create!
        subject.search('').to_a.should == [match]
      end

      it 'respects an existing scope chain' do
        match = subject.create!(:name => 'Abraham')
        no_match = subject.create!(:name => 'Elizabath')
        subject.scoped(:conditions => { :name => 'Abraham' }).search('').to_a.should == [match]
      end

    end

  end

  describe '.search_syntax' do

    it "should return the model's syntax definition when called without a block" do
      subject.search_syntax.should be_a(Dusen::Syntax)
    end

    it 'should be callable multiple times, appending additional syntax' do
      subject.search_syntax.fields.keys.should =~ ['text', 'email', 'city', 'role']
    end

  end

end


describe ActiveRecord::Base do

  describe 'for a model without an associated FULLTEXT table' do

    subject { User::WithoutFulltext }

    it_should_behave_like 'model with search syntax'

  end

  describe 'for a model with an associated FULLTEXT table' do

    subject { User::WithFulltext }

    it_should_behave_like 'model with search syntax'

    it 'should be shadowed by a Dusen::ActiveRecord::SearchText, which is created, updated and destroyed with the record' do
      user = User::WithFulltext.create!(:name => 'name', :email => 'email', :city => 'city')
      User::WithFulltext.index_search_texts

      search_texts = Dusen::ActiveRecord::SearchText.all
      search_texts.size.should == 1
      search_texts[0].words.should == 'name email city'
      search_texts[0].should_not be_stale

      user.reload
      user.update_attributes!(:email => 'changed_email')

      search_texts = Dusen::ActiveRecord::SearchText.all
      search_texts.size.should == 1
      search_texts[0].words.should == 'name email city'
      search_texts[0].should be_stale

      User::WithFulltext.index_search_texts

      search_texts = Dusen::ActiveRecord::SearchText.all
      search_texts.size.should == 1
      search_texts[0].words.should == 'name changed_email city'
      search_texts[0].should_not be_stale

      user.destroy

      search_texts = Dusen::ActiveRecord::SearchText.all
      search_texts.size.should be_zero
    end

    describe 'indexing fields from associated records' do

      it 'should allow to index fields from an associated record' do
        category = Recipe::Category.create!(:name => 'Rice')
        recipe = Recipe.create!(:name => 'Martini Chicken', :category => category)
        recipe.ingredients.create!(:name => 'Paprica')
        recipe.ingredients.create!(:name => 'Tomatoes')
        Recipe.search('Rice').to_a.should == [recipe]
        Recipe.search('Martini').to_a.should == [recipe]
        Recipe.search('Paprica').to_a.should == [recipe]
        Recipe.search('Tomatoes').to_a.should == [recipe]
      end

      context 'if the associated model has a .part_of_search_text_for directive' do

        it 'should automatically reindex itself when an associated record changes' do
          category = Recipe::Category.create!(:name => 'Rice')
          recipe = category.recipes.create!(:name => 'Martini Chicken')
          ingredient = recipe.ingredients.create!(:name => 'Paprica')
          category.update_attributes!(:name => 'Noodles')
          ingredient.update_attributes!(:name => 'Onions')
          Recipe.search('Noodles').to_a.should == [recipe]
          Recipe.search('Onion').to_a.should == [recipe]
          category.reload
          category.destroy
          Recipe.search('Noodles').to_a.should be_empty
        end

        #it 'should automatically reindex both containers if the container changes' do
        #  recipe1 = Recipe.create!(:name => 'Martini Chicken')
        #  recipe2 = Recipe.create!(:name => 'Whiskey Chicken')
        #  ingredient = recipe1.ingredients.create!(:name => 'Paprica')
        #  Recipe.search('Paprica').to_a.should == [recipe1]
        #  ingredient.update_attributes!(:recipe => recipe2)
        #  Recipe.search('Paprica').to_a.should == [recipe2]
        #end

      end

    end

    describe '#search_text' do

      it 'should return the currently indexable words for this record' do
        category = Recipe::Category.create!(:name => 'Rice')
        recipe = Recipe.create!(:name => 'Martini Chicken', :category => category)
        recipe.search_text.should == "Martini Chicken Rice"
      end

    end

  end

end
