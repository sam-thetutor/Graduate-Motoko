import Result "mo:base/Result";
import Text "mo:base/Text";
import Principal "mo:base/Principal";
import Nat "mo:base/Nat";
import Buffer "mo:base/Buffer";
import HashMap "mo:base/HashMap";
import Error "mo:base/Error";
import Nat64 "mo:base/Nat64";
import Time "mo:base/Time";
import Iter "mo:base/Iter";
import Hash "mo:base/Hash";
import Types "types";
import TokenTypes "../interfaces/token.types";
actor {

	type Result<A, B> = Result.Result<A, B>;
	type Member = Types.Member;
	type ProposalContent = Types.ProposalContent;
	type ProposalId = Types.ProposalId;
	type Proposal = Types.Proposal;
	type Vote = Types.Vote;
	type HttpRequest = Types.HttpRequest;
	type HttpResponse = Types.HttpResponse;

	// The principal of the Webpage canister associated with this DAO canister (needs to be updated with the ID of your Webpage canister)
	stable let canisterIdWebpage : Principal = Principal.fromText("aaaaa-aa");
	stable var manifesto = "Onboarding one developer at a time";
	stable let name = "Africa-Dev DAO";
	var goals = Buffer.Buffer<Text>(0);

	func natHash(n : Nat) : Hash.Hash {
		Text.hash(Nat.toText(n));
	};

	//hashmap to register new users
	stable var daoUserArray : [(Principal, Member)] = [(Principal.fromText("nkqop-siaaa-aaaaj-qa3qq-cai"), { name = "motoko_bootcamp"; role = #Mentor })];
	let daoUsers : HashMap.HashMap<Principal, Member> = HashMap.fromIter(daoUserArray.vals(), 16, Principal.equal, Principal.hash);
	//declare the token canister. replace with the canister
	let tokenCanister = actor ("jaamb-mqaaa-aaaaj-qa3ka-cai") : TokenTypes.Actor;

	var nextProposalId : Nat = 0;
	//store the proposals
	let proposalStore = HashMap.HashMap<ProposalId, Proposal>(0, Nat.equal, natHash);

	// Returns the name of the DAO
	public query func getName() : async Text {
		return name;
	};

	// Returns the manifesto of the DAO
	public query func getManifesto() : async Text {
		return manifesto;
	};

	// Returns the goals of the DAO
	public query func getGoals() : async [Text] {
		return Buffer.toArray(goals);
	};

	// Register a new member in the DAO with the given name and principal of the caller
	// Airdrop 10 MBC tokens to the new member
	// New members are always Student
	// Returns an error if the member already exists
	public shared ({ caller }) func registerMember(member : Member) : async Result<(), Text> {
		try {
			switch (daoUsers.get(caller)) {
				case (null) {

					let mintResults = await tokenCanister.mint(caller, 10);
					switch (mintResults) {
						case (#ok) {
							daoUsers.put(caller, member);
							return #ok();
						};
						case (#err(error)) {
							return #err("could not mint 10 MBT tokens for the new user :" # error);
						};
					};

				};
				case (?user) {
					return #err("member already exists");
				};
			};

		} catch (error) {

			return #err("error in registering new user :" # Error.message(error));
		};

	};

	// Get the member with the given principal
	// Returns an error if the member does not exist
	public query func getMember(p : Principal) : async Result<Member, Text> {
		switch (daoUsers.get(p)) {
			case (?user) { return #ok(user) };
			case (null) {
				return #err("no member with that principal found");
			};
		};
	};

	// Graduate the student with the given principal
	// Returns an error if the student does not exist or is not a student
	// Returns an error if the caller is not a mentor
	public shared ({ caller }) func graduate(student : Principal) : async Result<(), Text> {
		switch (daoUsers.get(caller)) {
			case (?admin) {
				if (admin.role != #Mentor) {
					return #err("caller is not a mentor");
				};

				switch (daoUsers.get(student)) {
					case (?stud) {
						if (stud.role != #Student) {
							return #err("user is not a student");
						};

						daoUsers.put(student, { stud with role = #Graduate });
						return #ok();

					};
					case (null) {
						return #err("student not found");
					};
				};

			};
			case (null) { return #err("admin not found") };
		};
	};

	// Create a new proposal and returns its id
	// Returns an error if the caller is not a mentor or doesn't own at least 1 MBC token
	public shared ({ caller }) func createProposal(content : ProposalContent) : async Result<ProposalId, Text> {
		switch (daoUsers.get(caller)) {
			case (?mentor) {
				if (mentor.role != #Mentor) {
					return #err("caller is not a mentor");
				};
				let balance = await tokenCanister.balanceOf(caller);
				if (balance < 1) {
					return #err("caller does not have enough balance");
				};

				let rr = await tokenCanister.burn(caller, 1);
				switch (await tokenCanister.burn(caller, 1)) {
					case (#ok) {

						let newProposal : Proposal = {
							id = nextProposalId;
							creator = caller;
							content;
							created = Time.now();
							executed = null;
							votes = [];
							voteScore = 0;
							status = #Open;
						};

						proposalStore.put(nextProposalId, newProposal);
						nextProposalId += 1;
						return #ok(nextProposalId -1);

					};
					case (_) {
						return #err("unable to burn the tokens");
					};
				};

			};
			case (null) { return #err("caller does not exist") };
		};
	};

	// Get the proposal with the given id
	// Returns an error if the proposal does not exist
	public query func getProposal(id : ProposalId) : async Result<Proposal, Text> {
		switch (proposalStore.get(id)) {
			case (?prop) { return #ok(prop) };
			case (null) { return #err("proposal not found") };
		};
	};

	// Returns all the proposals
	public query func getAllProposal() : async [Proposal] {
		return Iter.toArray(proposalStore.vals());
	};

	// Vote for the given proposal
	// Returns an error if the proposal does not exist or the member is not allowed to vote
	public shared ({ caller }) func voteProposal(proposalId : ProposalId, yesOrNo : Bool) : async Result<(), Text> {
		switch (daoUsers.get(caller)) {
			case (?user) {
				if (user.role == #Student) {
					return #err("students are not allowed to vote");
				};

				switch (proposalStore.get(proposalId)) {
					case (?proposal) {

						if (proposal.status != #Open) {
							return #err("proposal in no longer open");
						};

						let tokenBalance = await tokenCanister.balanceOf(caller);

						let votingPower = switch (user.role) {
							case (#Graduate) { tokenBalance };
							case (#Mentor) { tokenBalance * 5 };
							case (#Student) { 0 };
						};

						//calculate the new votescore
						let newVoteScore = switch (yesOrNo) {
							case (true) { proposal.voteScore + votingPower };
							case (false) { proposal.voteScore -votingPower };
						};

						var newExecuted : ?Time.Time = null;

						let newStatus = if (newVoteScore >= 100) {
							#Accepted;
						} else if (newVoteScore <= -100) {
							#Rejected;
						} else {
							#Open;
						};

						let newVotes = Buffer.fromArray<Vote>(proposal.votes);
						newVotes.add({
							member = caller;
							votingPower;
							yesOrNo;
						});

						switch (newStatus) {
							case (#Accepted) {
								_executeProposal(proposal.content);
								newExecuted := ?Time.now();
							};
							case (_) {};
						};

						let newProposal : Proposal = {
							id = proposal.id;
							content = proposal.content;
							creator = proposal.creator;
							created = proposal.created;
							executed = newExecuted;
							votes = Buffer.toArray(newVotes);
							voteScore = newVoteScore;
							status = newStatus;
						};
						proposalStore.put(proposal.id, newProposal);
						return #ok();

					};
					case (null) { return #err("proposal does not exist") };
				};

			};
			case (null) { return #err("user not found in the dao") };
		};
	};

	func _executeProposal(content : ProposalContent) : () {
		switch (content) {
			case (#ChangeManifesto(newManifesto)) {
				manifesto := newManifesto;
			};
			case (#AddMentor(mentorPrincipal)) {
				switch (daoUsers.get(mentorPrincipal)) {
					case (?mentor) {
						if (mentor.role != #Graduate) {
							return;
						};
						daoUsers.put(mentorPrincipal, { mentor with role = #Mentor });
					};
					case (null) {};
				};

			};
		};
		return;
	};

	// Returns the Principal ID of the Webpage canister associated with this DAO canister
	public query func getIdWebpage() : async Principal {
		return canisterIdWebpage;
	};

};
